use std::env;
use std::path::{Path, PathBuf};
use std::process::Command;
use walkdir::WalkDir;

fn main() {
    let base_dir = env::var("BASE_DIR")
        .unwrap_or_else(|_| {
            env::var("HOME")
                .map(|home| format!("{}/code", home))
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

fn find_git_repos(base_dir: &Path) -> Vec<PathBuf> {
    const IGNORED_DIRS: &[&str] = &["node_modules", "build", "out", "target", "dist", "coverage", "src"];
    const MAX_DEPTH: usize = 8; // Typische Projektstruktur-Tiefe

    let mut repos = Vec::with_capacity(1000);

    WalkDir::new(base_dir)
        .follow_links(false)
        .max_depth(MAX_DEPTH)
        .into_iter()
        .filter_entry(|entry| {
            let path = entry.path();
            let file_name = match path.file_name().and_then(|n| n.to_str()) {
                Some(name) => name,
                None => return false,
            };

            // Frühe Git-Repository-Erkennung
            if file_name == ".git" && path.is_dir() {
                if let Some(parent) = path.parent() {
                    repos.push(parent.to_path_buf());
                }
                return false; // Nicht in .git Verzeichnis hineingehen
            }

            // Normale Verzeichnis-Filterung
            !file_name.starts_with('.') && !IGNORED_DIRS.contains(&file_name)
        })
        .for_each(drop); // Iterator konsumieren, aber Ergebnisse ignorieren

    repos
}