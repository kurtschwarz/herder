//! The repository's layout: its working trees, branches and where each keeps
//! its `HEAD` and index.

use super::kind::{self, Opened, canonical};
use super::natural;
use crate::protocol::{Checkout, GitError, GitErrorCode, HostId, RepositoryKind, Worktree};
use std::fs;
use std::path::Path;
use std::time::UNIX_EPOCH;

fn failed(error: impl std::fmt::Display) -> GitError {
    GitError { code: GitErrorCode::Failed, message: error.to_string() }
}

/// Main working tree first, then branches in natural order, then detached
/// checkouts. Linked worktrees whose folder has gone missing are skipped: git
/// still lists them until pruned, but there is nothing to open.
pub fn worktrees(path: &str) -> Result<Vec<Worktree>, GitError> {
    let Some(Opened { repo, kind }) = kind::open(path) else {
        return Ok(Vec::new());
    };
    let mut result = Vec::new();

    match kind {
        RepositoryKind::MainWorkingTree => {
            if let (Some(workdir), Some(checkout)) = (repo.workdir(), checkout_of(&repo)) {
                result.push(Worktree {
                    host: HostId::local(),
                    path: kind::path_string(&canonical(workdir)),
                    checkout,
                    is_main_working_tree: true,
                    last_activity: last_activity(repo.git_dir()),
                });
            }
        }
        RepositoryKind::Bare => {}
        RepositoryKind::LinkedWorktree { .. } | RepositoryKind::NotARepository => {
            return Ok(Vec::new());
        }
    }

    let mut linked = Vec::new();
    for proxy in repo.worktrees().map_err(failed)? {
        let Ok(base) = proxy.base() else { continue };
        if !base.exists() {
            continue;
        }
        let git_dir = proxy.git_dir().to_path_buf();
        let Ok(tree) = proxy.into_repo_with_possibly_inaccessible_worktree() else {
            continue;
        };
        let Some(checkout) = checkout_of(&tree) else { continue };
        linked.push(Worktree {
            host: HostId::local(),
            path: kind::path_string(&canonical(&base)),
            checkout,
            is_main_working_tree: false,
            last_activity: last_activity(&git_dir),
        });
    }

    linked.sort_by(|a, b| match (&a.checkout, &b.checkout) {
        (Checkout::Branch { name: x }, Checkout::Branch { name: y }) => {
            natural::compare(x, y).then_with(|| a.path.cmp(&b.path))
        }
        (Checkout::Branch { .. }, Checkout::Detached { .. }) => std::cmp::Ordering::Less,
        (Checkout::Detached { .. }, Checkout::Branch { .. }) => std::cmp::Ordering::Greater,
        (Checkout::Detached { .. }, Checkout::Detached { .. }) => a.path.cmp(&b.path),
    });
    result.extend(linked);
    Ok(result)
}

/// Every local branch, loose and packed, in natural order. Empty for a folder
/// that is not the root of a main working tree or a bare repository.
pub fn branches(path: &str) -> Result<Vec<String>, GitError> {
    let Some(Opened { repo, kind }) = kind::open(path) else {
        return Ok(Vec::new());
    };
    if !matches!(kind, RepositoryKind::MainWorkingTree | RepositoryKind::Bare) {
        return Ok(Vec::new());
    }
    let platform = repo.references().map_err(failed)?;
    let mut names: Vec<String> = platform
        .local_branches()
        .map_err(failed)?
        .filter_map(Result::ok)
        .map(|reference| reference.name().shorten().to_string())
        .collect();
    names.sort_by(|a, b| natural::compare(a, b));
    Ok(names)
}

/// Where the working tree keeps its `index` and `HEAD`. For a linked worktree
/// that is `<main repository>/.git/worktrees/<name>`, which is not inside the
/// tree.
pub fn git_directory(path: &str) -> Option<String> {
    let Opened { repo, kind } = kind::open(path)?;
    matches!(kind, RepositoryKind::MainWorkingTree | RepositoryKind::LinkedWorktree { .. })
        .then(|| kind::path_string(&canonical(repo.git_dir())))
}

/// A branch, or the commit when `HEAD` is detached.
pub fn checkout(path: &str) -> Option<Checkout> {
    let Opened { repo, kind } = kind::open(path)?;
    matches!(kind, RepositoryKind::MainWorkingTree | RepositoryKind::LinkedWorktree { .. })
        .then(|| checkout_of(&repo))
        .flatten()
}

fn checkout_of(repo: &gix::Repository) -> Option<Checkout> {
    let head = repo.head().ok()?;
    if let Some(name) = head.referent_name() {
        return Some(Checkout::Branch { name: name.shorten().to_string() });
    }
    let id = head.id()?;
    Some(Checkout::Detached { sha: id.to_hex_with_len(7).to_string() })
}

/// The reflog's modification time: git appends to it on every commit and
/// checkout, so it tracks the working tree better than `HEAD` itself, which
/// only changes on a checkout.
fn last_activity(git_dir: &Path) -> Option<f64> {
    ["logs/HEAD", "HEAD"].iter().find_map(|name| {
        let modified = fs::metadata(git_dir.join(name)).ok()?.modified().ok()?;
        Some(modified.duration_since(UNIX_EPOCH).ok()?.as_secs_f64())
    })
}
