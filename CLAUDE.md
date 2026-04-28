# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

git-summary is a CLI tool that recursively finds Git repositories under a directory and displays a chronological summary of recent commits. Written in Zig 0.15+ using zig-clap for argument parsing.

## Build & Run Commands

```bash
zig build              # Build (output: zig-out/bin/git-summary)
zig build run -- [OPTIONS]  # Build and run with arguments
zig build -Doptimize=ReleaseFast -p ~/.local  # Install to ~/.local/bin
```

There are no tests or linting commands configured.

## Architecture

Single-file application in `src/main.zig`:

- **Argument parsing** (`main`): `zig-clap` with compile-time param definitions. See `README.md` for the user-facing flag list.
- **Directory walking** (`findGitRepos`): Recursively searches for `.git` directories, skipping dotfiles and a hardcoded `ignored_dirs` list.
- **Git interaction** (`runGit`, `collectCommits`): Shells out to `git log` / `git config` via `std.process.Child.run`, parses `%ad|%H|%s` output.
- **Output**: Commits sorted chronologically, grouped by date with weekday names (Tomohiko Sakamoto's algorithm).

Version is sourced from `build.zig.zon` via build options (`@import("config").version`).
