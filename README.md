# Git Summary

A command-line tool that recursively searches for Git repositories and summarizes your recent commits across multiple projects.

## Description

Git Summary helps you keep track of your work across multiple Git repositories. It recursively searches for Git repositories in a specified directory and displays a chronological summary of your commits, making it easy to see what you've been working on recently.

Features:
- Recursively finds all Git repositories in a directory
- Filters commits by author and date range
- Organizes commits by date with a clean, readable output
- Ignores common directories like node_modules, build, target, etc.

## Installation

### Prerequisites
- [Zig](https://ziglang.org/download/) (0.15+)
- Git

### Building from source

1. Clone the repository:
   ```
   git clone https://github.com/cdietze/git-summary.git
   cd git-summary
   ```

2. Build the project:
   ```
   zig build
   ```

3. Run the project directly (for development):
   ```
   zig build run -- [OPTIONS]
   ```

4. The binary will be available at `zig-out/bin/git-summary`

5. Optionally, install it to a custom prefix:
   ```
   zig build -Doptimize=ReleaseFast -p ~/.local
   ```

## Usage

Basic usage:
```
git-summary [OPTIONS] [DIR]
```

### Options

- `[DIR]`: Base directory to search for git repositories [default: .]
- `-s, --since <SINCE>`: Time range for commits [default: "1 week ago"]
- `-a, --author <AUTHOR>`: Author name for filtering commits (defaults to git config user.name)
- `-m, --max-depth <DEPTH>`: Maximum depth for repository search [default: 8]
- `-e, --exclude <DIR>...`: Directories to exclude from search (name or path, repeatable)
- `-h, --help`: Print help
- `-v, --version`: Print version and exit

### Examples

Show your commits from the last week in the current directory and subdirectories:
```
git-summary
```

Show your commits from the last month in a specific directory:
```
git-summary --since "1 month ago" ~/projects
```

Show commits by a specific author in the last 3 days:
```
git-summary --since "3 days ago" --author "John Doe"
```

Limit the search depth to 3 levels:
```
git-summary --max-depth 3
```

Exclude one or more directories from the search:
```
git-summary --exclude vendor --exclude ~/projects/archive
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
