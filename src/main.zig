const std = @import("std");
const clap = @import("clap");
const Allocator = std.mem.Allocator;

const version = @import("config").version;

const Commit = struct {
    date: []const u8,
    time: []const u8,
    repo: []const u8,
    message: []const u8,
};

const ignored_dirs: []const []const u8 = &.{
    "node_modules", "build", "out", "target", "dist", "coverage", "src",
};

const weekday_names = [_][]const u8{
    "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
};

const params = clap.parseParamsComptime(
    \\-h, --help                 Display this help and exit.
    \\-v, --version              Print version and exit.
    \\-s, --since <str>          Time range for commits [default: 1 week ago]
    \\-a, --author <str>         Author name (default: git config user.name)
    \\-m, --max-depth <usize>    Max search depth [default: 8]
    \\<str>
    \\
);

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    var arena_state = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = arena,
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        var help_buf: [4096]u8 = undefined;
        var help_w = std.fs.File.stderr().writer(&help_buf);
        clap.help(&help_w.interface, clap.Help, &params, .{}) catch {};
        help_w.interface.flush() catch {};
        return;
    }

    if (res.args.version != 0) {
        try std.fs.File.stdout().writeAll("git-summary " ++ version ++ "\n");
        return;
    }

    const dir = res.positionals[0] orelse ".";
    const since = res.args.since orelse "1 week ago";
    const max_depth = res.args.@"max-depth" orelse 8;

    const out = std.fs.File.stdout();
    var buf: [4096]u8 = undefined;
    var stdout = out.writer(&buf);
    const w = &stdout.interface;

    const real_path = std.fs.cwd().realpathAlloc(arena, dir) catch dir;
    try out.writeAll(try std.fmt.allocPrint(arena, "\xf0\x9f\x94\x8d Recursively searching for Git repositories under: {s}\n", .{real_path}));

    const author: []const u8 = res.args.author orelse
        runGit(arena, null, &.{ "config", "user.name" }) catch "unknown";

    try out.writeAll(try std.fmt.allocPrint(arena, "\xf0\x9f\x93\x85 Showing commits since: {s}\n", .{since}));
    try out.writeAll(try std.fmt.allocPrint(arena, "\xf0\x9f\x91\xa4 Filtering commits by author: {s}\n", .{author}));

    var repos: std.ArrayList([]const u8) = .empty;
    try findGitRepos(arena, dir, max_depth, 0, &repos);

    const count = repos.items.len;
    try out.writeAll(try std.fmt.allocPrint(arena, "\xf0\x9f\x93\xa6 Found {} Git {s}\n", .{
        count,
        if (count == 1) @as([]const u8, "repository") else "repositories",
    }));

    if (count == 0) {
        try out.writeAll("\xe2\x9a\xa0\xef\xb8\x8f No Git repositories found.\n");
        return;
    }

    const since_arg = try std.fmt.allocPrint(arena, "--since={s}", .{since});
    const author_arg = try std.fmt.allocPrint(arena, "--author={s}", .{author});

    var commits: std.ArrayList(Commit) = .empty;
    for (repos.items) |repo| {
        try collectCommits(arena, repo, since_arg, author_arg, &commits);
    }

    std.mem.sort(Commit, commits.items, {}, struct {
        fn lessThan(_: void, a: Commit, b: Commit) bool {
            return switch (std.mem.order(u8, a.date, b.date)) {
                .lt => true,
                .gt => false,
                .eq => std.mem.order(u8, a.time, b.time) == .lt,
            };
        }
    }.lessThan);

    var last_date: []const u8 = "";
    for (commits.items) |commit| {
        if (!std.mem.eql(u8, commit.date, last_date)) {
            try w.writeAll("--------------------------------------------------\n");
            try w.print("\xf0\x9f\x93\x85 {s}\n", .{commit.date});
            last_date = commit.date;
        }
        try w.print("{s} - {s} - {s}\n", .{
            commit.time,
            std.fs.path.basename(commit.repo),
            commit.message,
        });
    }
    try w.flush();
}

// --- Git interaction ---

fn runGit(allocator: Allocator, repo: ?[]const u8, args: []const []const u8) ![]const u8 {
    const prefix_len: usize = if (repo != null) 3 else 1;
    if (prefix_len + args.len > 16) return error.TooManyArgs;

    var argv_buf: [16][]const u8 = undefined;
    argv_buf[0] = "git";
    if (repo) |r| {
        argv_buf[1] = "-C";
        argv_buf[2] = r;
    }
    @memcpy(argv_buf[prefix_len .. prefix_len + args.len], args);
    const argv = argv_buf[0 .. prefix_len + args.len];

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });

    switch (result.term) {
        .Exited => |code| if (code != 0) return error.CommandFailed,
        else => return error.CommandFailed,
    }

    return std.mem.trimRight(u8, result.stdout, "\n\r ");
}

fn collectCommits(
    allocator: Allocator,
    repo: []const u8,
    since_arg: []const u8,
    author_arg: []const u8,
    commits: *std.ArrayList(Commit),
) !void {
    const output = runGit(allocator, repo, &.{
        "log",
        since_arg,
        author_arg,
        "--pretty=format:%ad|%H|%s",
        "--date=format:%Y-%m-%d %H:%M",
    }) catch |err| switch (err) {
        error.CommandFailed => return,
        else => return err,
    };

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        const first_pipe = std.mem.indexOfScalar(u8, line, '|') orelse continue;
        const rest = line[first_pipe + 1 ..];
        const second_pipe = std.mem.indexOfScalar(u8, rest, '|') orelse continue;
        const message = rest[second_pipe + 1 ..];
        const datetime = line[0..first_pipe];

        const space = std.mem.indexOfScalar(u8, datetime, ' ') orelse continue;
        const date_str = datetime[0..space];
        const time_str = datetime[space + 1 ..];

        const date_display = formatDateWithWeekday(allocator, date_str) catch date_str;

        try commits.append(allocator, .{
            .date = date_display,
            .time = time_str,
            .repo = repo,
            .message = message,
        });
    }
}

// --- Directory walking ---

fn findGitRepos(
    allocator: Allocator,
    base: []const u8,
    max_depth: usize,
    depth: usize,
    repos: *std.ArrayList([]const u8),
) !void {
    if (depth > max_depth) return;

    var dir = std.fs.cwd().openDir(base, .{ .iterate = true }) catch |err| {
        if (err == error.AccessDenied) {
            std.debug.print("\xe2\x9a\xa0\xef\xb8\x8f Skipping {s}: permission denied\n", .{base});
        }
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;

        if (std.mem.eql(u8, entry.name, ".git")) {
            try repos.append(allocator, try allocator.dupe(u8, base));
            continue;
        }

        if (entry.name[0] == '.') continue;
        if (isIgnored(entry.name)) continue;

        const sub = try std.fs.path.join(allocator, &.{ base, entry.name });
        try findGitRepos(allocator, sub, max_depth, depth + 1, repos);
    }
}

fn isIgnored(name: []const u8) bool {
    for (ignored_dirs) |d| {
        if (std.mem.eql(u8, name, d)) return true;
    }
    return false;
}

// --- Date utilities ---

fn formatDateWithWeekday(allocator: Allocator, date_str: []const u8) ![]const u8 {
    if (date_str.len != 10) return date_str;

    const year = try std.fmt.parseInt(i32, date_str[0..4], 10);
    const month = try std.fmt.parseInt(u32, date_str[5..7], 10);
    const day = try std.fmt.parseInt(u32, date_str[8..10], 10);

    const dow = dayOfWeek(year, month, day);
    return std.fmt.allocPrint(allocator, "{s} ({s})", .{ date_str, weekday_names[dow] });
}

/// Tomohiko Sakamoto's algorithm. Returns 0=Sunday .. 6=Saturday.
fn dayOfWeek(y: i32, m: u32, d: u32) usize {
    const t = [_]i32{ 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 };
    const yy = if (m < 3) y - 1 else y;
    const raw = @mod(
        yy + @divTrunc(yy, 4) - @divTrunc(yy, 100) + @divTrunc(yy, 400) + t[m - 1] + @as(i32, @intCast(d)),
        7,
    );
    return @intCast(raw);
}
