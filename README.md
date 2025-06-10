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
- Rust and Cargo (install from [rustup.rs](https://rustup.rs/))
- Git

### Building from source

1. Clone the repository:
   ```
   git clone <repository-url>
   cd git-summary
   ```

2. Build the project:
   ```
   cargo build --release
   ```

3. The binary will be available at `target/release/git-summary`

4. Optionally, install it to your system:
   ```
   cargo install --path .
   ```

## Usage

Basic usage:
```
git-summary [OPTIONS]
```

### Options

- `--dir <DIR>`: Base directory to search for git repositories [default: .]
- `--since <SINCE>`: Time range for commits [default: "1 week ago"]
- `--author <AUTHOR>`: Author name for filtering commits (defaults to git config user.name)
- `--max-depth <MAX_DEPTH>`: Maximum depth for repository search [default: 8]

### Examples

Show your commits from the last week in the current directory and subdirectories:
```
git-summary
```

Show your commits from the last month in a specific directory:
```
git-summary --dir ~/projects --since "1 month ago"
```

Show commits by a specific author in the last 3 days:
```
git-summary --since "3 days ago" --author "John Doe"
```

Limit the search depth to 3 levels:
```
git-summary --max-depth 3
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
