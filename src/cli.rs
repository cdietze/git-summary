use clap::Parser;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
pub struct Cli {
    /// Base directory to search for git repositories
    #[arg(default_value = ".")]
    pub dir: PathBuf,

    /// Time range for commits (e.g. "1 week ago")
    #[arg(short, long, default_value = "1 week ago")]
    pub since: String,

    /// Author name for filtering commits (defaults to git config user.name)
    #[arg(short, long)]
    pub author: Option<String>,

    /// Maximum depth for repository search
    #[arg(short, long, default_value_t = 8)]
    pub max_depth: usize,
}
