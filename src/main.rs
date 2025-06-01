use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::collections::HashSet;

fn main() {
    let base_dir = env::var("BASE_DIR")
        .unwrap_or_else(|_| {
            env::var("HOME")
                .map(|home| format!("{}/code/cpd", home))
                .unwrap_or_else(|_| ".".to_string())
        });
    
    let since = "1 week ago";
    let author = get_git_user_name().unwrap_or_else(|| "unknown".to_string());
    
    println!("📅 Zeige Commits seit: {}", since);
    println!("👤 Autor: {}", author);
    
    let base_path = Path::new(&base_dir);
    println!("🔍 Suche rekursiv nach Git-Repositories unter: {}", base_path.display());
    
    let repos = find_git_repos(base_path);
    println!("📦 Habe {} Git-Repository(s) gefunden.", repos.len());

    if repos.is_empty() {
        println!("⚠️ Keine Git-Repositories gefunden.");
    } else {
        for repo in repos {
            if !has_commits(&repo) {
                continue;
            }

            let log = run_git_log(&repo, since, &author);
            if let Some(output) = log {
                if !output.trim().is_empty() {
                    println!("--------------------------------------------------");
                    println!("📁 Repository: {}", repo.display());
                    println!("{}", output);
                }
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
                println!("⚠️ Fehler beim Ausführen von '{}': {}", command.join(" "), error);
                None
            }
        }
        Err(e) => {
            println!("⚠️ Ausnahme aufgetreten: {}", e);
            None
        }
    }
}

fn run_git_log(repo_dir: &Path, since: &str, author: &str) -> Option<String> {
    let args = [
        "git", "log",
        &format!("--since={}", since),
        &format!("--author={}", author),
        "--pretty=format:%C(yellow)%h %C(cyan)%ad %Cgreen%an %Creset%s",
        "--date=short"
    ];
    
    run_command(&args, Some(repo_dir))
}

use walkdir::WalkDir;

fn find_git_repos(base_dir: &Path) -> Vec<PathBuf> {
    const IGNORED_DIRS: &[&str] = &["node_modules", "build", "out", "target", ".idea", ".vscode"];

    let ignored_dirs: HashSet<&str> = IGNORED_DIRS.iter().cloned().collect();

    WalkDir::new(base_dir)
        .follow_links(false)
        .max_depth(10) // Tiefenbegrenzung hinzufügen
        .into_iter()
        .filter_entry(|entry| should_enter_directory(entry, &ignored_dirs))
        .filter_map(|entry| {
            match entry {
                Ok(dir_entry) => {
                    let path = dir_entry.path();
                    if path.file_name().and_then(|n| n.to_str()) == Some(".git") && path.is_dir() {
                        path.parent().map(|p| p.to_path_buf())
                    } else {
                        None
                    }
                }
                Err(_) => None,
            }
        })
        .collect()
}

fn should_enter_directory(entry: &walkdir::DirEntry, ignored_dirs: &HashSet<&str>) -> bool {
    let file_name = entry.file_name().to_str().unwrap_or("");

    if file_name == ".git" {
        return true;
    }

    !file_name.starts_with('.') && !ignored_dirs.contains(file_name)
}