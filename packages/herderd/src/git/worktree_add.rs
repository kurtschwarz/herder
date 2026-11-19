//! Adding a working tree, the one operation that changes the repository.

use super::cli;
use super::kind::{self, Opened, canonical};
use crate::protocol::{GitError, GitErrorCode, RepositoryKind};
use std::fs;
use std::path::Path;

fn invalid(message: &str) -> GitError {
    GitError { code: GitErrorCode::InvalidRequest, message: message.to_string() }
}

/// Adds a working tree at `worktree` on a new branch cut from `base`.
pub fn add(
    path: &str,
    worktree: &str,
    new_branch: &str,
    base: &str,
    exclude: Option<&str>,
) -> Result<String, GitError> {
    // A leading dash would be read as an option.
    if new_branch.starts_with('-') || base.starts_with('-') {
        return Err(invalid("a branch name cannot start with a dash"));
    }
    let repository = canonical(Path::new(path));
    if let (Some(folder), Some(Opened { repo, kind: RepositoryKind::MainWorkingTree })) =
        (exclude, kind::open(path))
    {
        exclude_folder(repo.git_dir(), folder);
    }

    cli::run_checked(&repository, &["worktree", "add", "-b", new_branch, worktree, base])?;
    Ok(worktree.to_string())
}

/// Keeps `folder` out of the main working tree's status, since a nested
/// worktree's own files would otherwise show as an untracked folder. Anchored,
/// so only this folder at the top is ignored, not any folder of the same name
/// deeper down. Best effort: a failure here only means the folder shows up as
/// untracked.
fn exclude_folder(git_dir: &Path, folder: &str) {
    let entry = format!("/{folder}/");
    let info = git_dir.join("info");
    let file = info.join("exclude");
    let existing = fs::read_to_string(&file).unwrap_or_default();
    if existing.lines().any(|line| line == entry) {
        return;
    }
    let _ = fs::create_dir_all(&info);
    let separator = if existing.is_empty() || existing.ends_with('\n') { "" } else { "\n" };
    let _ = fs::write(&file, format!("{existing}{separator}{entry}\n"));
}
