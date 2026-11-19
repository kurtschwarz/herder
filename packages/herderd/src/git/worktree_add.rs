//! Adding a working tree, the one operation that changes the repository.

use super::kind::{self, Opened};
use crate::protocol::{GitError, GitErrorCode, RepositoryKind};
use gix::refs::transaction::PreviousValue;
use gix::worktree::add::Head;
use std::fs;
use std::path::Path;
use std::sync::atomic::AtomicBool;

fn invalid(message: impl Into<String>) -> GitError {
    GitError { code: GitErrorCode::InvalidRequest, message: message.into() }
}

fn failed(message: impl Into<String>) -> GitError {
    GitError { code: GitErrorCode::Failed, message: message.into() }
}

/// Adds a working tree at `worktree` on a new branch cut from `base`, as
/// `git worktree add -b` does, except that no hooks run.
///
/// `gix` checks out only a branch that already exists, so the branch is made
/// first and deleted again if the worktree cannot be added.
pub fn add(
    path: &str,
    worktree: &str,
    new_branch: &str,
    base: &str,
    exclude: Option<&str>,
) -> Result<String, GitError> {
    if new_branch.starts_with('-') || base.starts_with('-') {
        return Err(invalid("a branch name cannot start with a dash"));
    }
    let Some(Opened { repo, kind }) = kind::open(path) else {
        return Err(invalid(format!("{path} is not a repository")));
    };
    if !matches!(kind, RepositoryKind::MainWorkingTree | RepositoryKind::Bare) {
        return Err(invalid(format!("{path} is not a main working tree or a bare repository")));
    }
    // Opened again with the user's own config, which the read-only operations
    // leave out: the branch and the new `HEAD` get reflog entries, and those
    // name whoever made them.
    let mut repo = gix::open(repo.git_dir()).map_err(|error| failed(error.to_string()))?;
    if repo.committer().is_none_or(|committer| committer.is_err()) {
        // No identity configured. It goes in as config rather than on this
        // handle: adding a worktree opens the new one afresh, and that handle
        // would not carry it, so the new `HEAD`'s reflog could not be written.
        let (name, email) = fallback_identity();
        let options = gix::open::Options::isolated()
            .config_overrides([format!("user.name={name}"), format!("user.email={email}")]);
        repo = gix::open_opts(repo.git_dir(), options).map_err(|error| failed(error.to_string()))?;
    }

    let name = format!("refs/heads/{new_branch}");
    if repo.try_find_reference(name.as_str()).ok().flatten().is_some() {
        return Err(failed(format!("a branch named '{new_branch}' already exists")));
    }
    let target = repo
        .rev_parse_single(base)
        .ok()
        .and_then(|id| id.object().ok()?.peel_to_commit().ok())
        .ok_or_else(|| failed(format!("invalid reference: {base}")))?;
    if Path::new(worktree).exists() && fs::read_dir(worktree).is_ok_and(|mut d| d.next().is_some())
    {
        return Err(failed(format!("'{worktree}' already exists")));
    }

    if let (Some(folder), RepositoryKind::MainWorkingTree) = (exclude, &kind) {
        exclude_folder(repo.git_dir(), folder);
    }

    let branch = repo
        .reference(
            name.as_str(),
            target.id,
            PreviousValue::MustNotExist,
            format!("branch: Created from {base}"),
        )
        .map_err(|error| failed(error.to_string()))?;

    let added = repo.add_worktree(
        worktree,
        Head::Attached(branch.name().to_owned()),
        gix::progress::Discard,
        &AtomicBool::new(false),
    );
    if let Err(error) = added {
        let _ = branch.delete();
        return Err(failed(error.to_string()));
    }
    Ok(worktree.to_string())
}

/// Who git itself names when no identity is configured: the login name, at
/// this host.
fn fallback_identity() -> (String, String) {
    let user = std::env::var("USER").unwrap_or_else(|_| "herderd".to_string());
    let mut buffer = [0u8; 256];
    // SAFETY: the buffer outlives the call and its length is passed with it.
    let ok = unsafe { libc::gethostname(buffer.as_mut_ptr().cast(), buffer.len()) } == 0;
    let host = ok
        .then(|| {
            let end = buffer.iter().position(|&b| b == 0).unwrap_or(buffer.len());
            String::from_utf8_lossy(&buffer[..end]).into_owned()
        })
        .filter(|host| !host.is_empty())
        .unwrap_or_else(|| "localhost".to_string());
    let email = format!("{user}@{host}");
    (user, email)
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
