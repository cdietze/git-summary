const std = @import("std");
const Allocator = std.mem.Allocator;

const Config = struct {
    dir: []const u8 = ".",
    since: []const u8 = "1 week ago",
    author: ?[]const u8 = null,
    max_depth: usize = 8,
};

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

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    var arena_state = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const config = parseArgs();

    const out = std.fs.File.stdout();
    var buf: [4096]u8 = undefined;
    var stdout = out.writer(&buf);
    const w = &stdout.interface;

    const real_path = std.fs.cwd().realpathAlloc(arena, config.dir) catch config.dir;
    try out.writeAll(try std.fmt.allocPrint(arena, "\xf0\x9f\x94\x8d Recursively searching for Git repositories under: {s}\n", .{real_path}));

    const author: []const u8 = config.author orelse
        runGit(arena, null, &.{ "config", "user.name" }) catch "unknown";

    try out.writeAll(try std.fmt.allocPrint(arena, "\xf0\x9f\x93\x85 Showing commits since: {s}\n", .{config.since}));
    try out.writeAll(try std.fmt.allocPrint(arena, "\xf0\x9f\x91\xa4 Filtering commits by author: {s}\n", .{author}));

    var repos: std.ArrayList([]const u8) = .empty;
    defer repos.deinit(arena);
    try findGitRepos(arena, config.dir, config.max_depth, 0, &repos);

    const count = repos.items.len;
    try out.writeAll(try std.fmt.allocPrint(arena, "\xf0\x9f\x93\xa6 Found {} Git {s}\n", .{
        count,
        if (count == 1) @as([]const u8, "repository") else "repositories",
    }));

    if (count == 0) {
        try out.writeAll("\xe2\x9a\xa0\xef\xb8\x8f No Git repositories found.\n");
        return;
    }

    var commits: std.ArrayList(Commit) = .empty;
    defer commits.deinit(arena);
    for (repos.items) |repo| {
        _ = runGit(arena, repo, &.{ "rev-parse", "HEAD" }) catch continue;
        try collectCommits(arena, repo, config.since, author, &commits);
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

// --- Argument parsing ---

fn parseArgs() Config {
    var config = Config{};
    var args = std.process.args();
    _ = args.skip();

    while (args.next()) |arg| {
        if (eql(arg, "-s") or eql(arg, "--since")) {
            config.since = args.next() orelse fatal("missing value for --since");
        } else if (eql(arg, "-a") or eql(arg, "--author")) {
            config.author = args.next() orelse fatal("missing value for --author");
        } else if (eql(arg, "-m") or eql(arg, "--max-depth")) {
            const val = args.next() orelse fatal("missing value for --max-depth");
            config.max_depth = std.fmt.parseInt(usize, val, 10) catch fatal("invalid --max-depth");
        } else if (eql(arg, "-h") or eql(arg, "--help")) {
            printUsage();
            std.process.exit(0);
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            config.dir = arg;
        } else {
            std.debug.print("unknown option: {s}\n", .{arg});
            std.process.exit(1);
        }
    }
    return config;
}

fn printUsage() void {
    var ubuf: [4096]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&ubuf);
    const w = &stdout.interface;
    w.writeAll(
        \\Usage: git-summary [OPTIONS] [DIR]
        \\
        \\Arguments:
        \\  [DIR]  Base directory to search for git repositories [default: .]
        \\
        \\Options:
        \\  -s, --since <SINCE>          Time range for commits [default: 1 week ago]
        \\  -a, --author <AUTHOR>        Author name (default: git config user.name)
        \\  -m, --max-depth <DEPTH>      Max search depth [default: 8]
        \\  -h, --help                   Print help
        \\
    ) catch {};
    w.flush() catch {};
}

// --- Git interaction ---

fn runGit(allocator: Allocator, repo: ?[]const u8, args: []const []const u8) ![]const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, "git");
    if (repo) |r| {
        try argv.append(allocator, "-C");
        try argv.append(allocator, r);
    }
    try argv.appendSlice(allocator, args);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv.items,
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
    since: []const u8,
    author: []const u8,
    commits: *std.ArrayList(Commit),
) !void {
    const since_arg = try std.fmt.allocPrint(allocator, "--since={s}", .{since});
    const author_arg = try std.fmt.allocPrint(allocator, "--author={s}", .{author});

    const output = runGit(allocator, repo, &.{
        "log",
        since_arg,
        author_arg,
        "--pretty=format:%ad|%H|%s",
        "--date=format:%Y-%m-%d %H:%M",
    }) catch return;

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

    var dir = std.fs.cwd().openDir(base, .{ .iterate = true }) catch return;
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

// --- Helpers ---

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn fatal(msg: []const u8) noreturn {
    std.debug.print("error: {s}\n", .{msg});
    std.process.exit(1);
}
