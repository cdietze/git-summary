use std::path::{Path, PathBuf};
use std::process::Command;
use std::collections::BTreeMap;
use walkdir::WalkDir;
use chrono::{NaiveDate, Datelike};

mod cli;
use cli::Cli;
use clap::Parser;

fn main() {
    let cli = Cli::parse();
    let base_dir = &cli.dir;

    println!("🔍 Recursively searching for Git repositories under: {}", std::fs::canonicalize(base_dir)
        .unwrap_or_else(|_| base_dir.to_path_buf()).display());

    let since = &cli.since;
    let author = cli.author.clone().unwrap_or_else(|| get_git_user_name().unwrap_or_else(|| "unknown".to_string()));

    println!("📅 Showing commits since: {}", since);
    println!("👤 Filtering commits by author: {}", author);

    let repos = find_git_repos(base_dir, cli.max_depth);
    println!("📦 Found {} Git {}", repos.len(),
    if repos.len() == 1 { "repository" } else { "repositories" });

    if repos.is_empty() {
        println!("⚠️ No Git repositories found.");
    } else {
        let mut commits_by_date: BTreeMap<String, Vec<(String, String)>> = BTreeMap::new();

        for repo in repos {
            if !has_commits(&repo) {
                continue;
            }

            let commits = get_commits(&repo, since, &author);
            for (date, message) in commits {
                commits_by_date.entry(date)
                    .or_insert_with(Vec::new)
                    .push((repo.display().to_string(), message));
            }
        }

        for (date, commits) in commits_by_date.iter().rev() {
            println!("--------------------------------------------------");
            println!("📅 {}", date);
            for (repo, message) in commits {
                println!("📁 {} - {}",
                    repo.split('/').last().unwrap_or(repo),
                    message);
            }
        }
    }
}

fn get_git_user_name() -> Option<String> {
    run_command(&["git", "config", "user.name"], None)
        .map(|s| s.trim().to_string())
}

fn has_commits(repo_dir: &Path) -> bool {
    Command::new("git")
        .args(&["rev-parse", "HEAD"])
        .current_dir(repo_dir)
        .output()
        .map(|output| output.status.success())
        .unwrap_or(false)
}

fn run_command(command: &[&str], working_dir: Option<&Path>) -> Option<String> {
    let mut cmd = Command::new(command[0]);
    cmd.args(&command[1..]);

    if let Some(dir) = working_dir {
        cmd.current_dir(dir);
    }

    match cmd.output() {
        Ok(output) => {
            if output.status.success() {
                Some(String::from_utf8_lossy(&output.stdout).to_string())
            } else {
                let error = String::from_utf8_lossy(&output.stderr);
                println!("⚠️ Error executing '{}': {}", command.join(" "), error);
                None
            }
        }
        Err(e) => {
            println!("⚠️ Exception occurred: {}", e);
            None
        }
    }
}

fn get_commits(repo_dir: &Path, since: &str, author: &str) -> Vec<(String, String)> {
    let args = [
        "git", "log",
        &format!("--since={}", since),
        &format!("--author={}", author),
        "--pretty=format:%ad|%s",
        "--date=short"
    ];

    if let Some(output) = run_command(&args, Some(repo_dir)) {
        output.lines()
            .filter_map(|line| {
                let parts: Vec<&str> = line.splitn(2, '|').collect();
                if parts.len() == 2 {
                    if let Ok(date) = NaiveDate::parse_from_str(parts[0], "%Y-%m-%d") {
                        let weekday = match date.weekday() {
                            chrono::Weekday::Mon => "Monday",
                            chrono::Weekday::Tue => "Tuesday",
                            chrono::Weekday::Wed => "Wednesday",
                            chrono::Weekday::Thu => "Thursday",
                            chrono::Weekday::Fri => "Friday",
                            chrono::Weekday::Sat => "Saturday",
                            chrono::Weekday::Sun => "Sunday",
                        };
                        Some((format!("{} ({})", parts[0], weekday), parts[1].to_string()))
                    } else {
                        Some((parts[0].to_string(), parts[1].to_string()))
                    }
                } else {
                    None
                }
            })
            .collect()
    } else {
        Vec::new()
    }
}

fn find_git_repos(base_dir: &Path, max_depth: usize) -> Vec<PathBuf> {
    const IGNORED_DIRS: &[&str] = &["node_modules", "build", "out", "target", "dist", "coverage", "src"];

    let mut repos = Vec::with_capacity(1000);

    WalkDir::new(base_dir)
        .follow_links(false)
        .max_depth(max_depth)
        .into_iter()
        .filter_entry(|entry| {
            let path = entry.path();
            let file_name = match path.file_name().and_then(|n| n.to_str()) {
                Some(name) => name,
                None => return false,
            };

            // Early Git repository detection
            if file_name == ".git" && path.is_dir() {
                if let Some(parent) = path.parent() {
                    repos.push(parent.to_path_buf());
                }
                return false; // Don't descend into .git directory
            }

            // Normal directory filtering
            !file_name.starts_with('.') && !IGNORED_DIRS.contains(&file_name)
        })
        .for_each(drop); // Consume iterator but ignore results

    repos
}
