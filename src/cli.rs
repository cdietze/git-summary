use clap::Parser;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
pub(crate) struct Cli {
    /// Base directory to search for git repositories
    #[arg(default_value = ".")]
    pub(crate) dir: PathBuf,

    /// Time range for commits (e.g. "1 week ago")
    #[arg(short, long, default_value = "1 week ago")]
    pub(crate) since: String,

    /// Author name for filtering commits (defaults to git config user.name)
    #[arg(short, long)]
    pub(crate) author: Option<String>,

    /// Maximum depth for repository search
    #[arg(short, long, default_value_t = 8)]
    pub(crate) max_depth: usize,
}
