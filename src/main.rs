use std::env;
use std::ffi::OsStr;
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
    const GIT_DIR: &str = ".git";

    // Für kleine Arrays ist lineares Suchen oft schneller als HashSet
    let mut repos = Vec::with_capacity(100); // Geschätzte Anzahl Repositories

    WalkDir::new(base_dir)
        .follow_links(false)
        .max_depth(MAX_DEPTH)
        .into_iter()
        .filter_entry(|entry| should_enter_directory_optimized(entry, IGNORED_DIRS))
        .filter_map(|entry| {
            let dir_entry = entry.ok()?;
            let path = dir_entry.path();

            // OsStr verwenden um String-Konvertierung zu vermeiden
            if path.file_name() == Some(OsStr::new(GIT_DIR)) && path.is_dir() {
                path.parent().map(PathBuf::from)
            } else {
                None
            }
        })
        .for_each(|repo| repos.push(repo));

    repos.shrink_to_fit(); // Unnötigen Speicher freigeben
    repos
}

fn should_enter_directory_optimized(entry: &walkdir::DirEntry, ignored_dirs: &[&str]) -> bool {
    let file_name = match entry.file_name().to_str() {
        Some(name) => name,
        None => return false, // Nicht-UTF8 Namen überspringen
    };

    // .git Verzeichnisse betreten
    if file_name == ".git" {
        return true;
    }

    // Versteckte Verzeichnisse überspringen (außer .git)
    if file_name.starts_with('.') {
        return false;
    }

    // Für kleine Arrays ist lineares Suchen schneller als HashSet
    !ignored_dirs.contains(&file_name)
}