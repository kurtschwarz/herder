//! Refs, commits and what a revision contained, read with `gix`.

use super::kind;
use crate::protocol::{ChangeSummary, Commit, GitError, GitErrorCode, Ref, RefKind};
use gix::bstr::ByteSlice;
use std::path::{Path, PathBuf};

fn failed(error: impl std::fmt::Display) -> GitError {
    GitError { code: GitErrorCode::Failed, message: error.to_string() }
}

/// The working tree's root, resolved, and its repository.
fn open(path: &str) -> Option<(PathBuf, gix::Repository)> {
    let repo = kind::working_tree(path)?;
    let root = kind::canonical(repo.workdir()?);
    Some((root, repo))
}

/// `origin/HEAD` if it is set and exists, else `main`, else `master`. `None`
/// when none of them exists.
fn default_branch(repo: &gix::Repository) -> Option<String> {
    let origin =
        repo.try_find_reference("refs/remotes/origin/HEAD").ok().flatten().and_then(|head| {
            match head.target() {
                gix::refs::TargetRef::Symbolic(name) => Some(name.shorten().to_string()),
                gix::refs::TargetRef::Object(_) => None,
            }
        });
    origin
        .into_iter()
        .chain(["main".to_string(), "master".to_string()])
        .find(|name| !name.is_empty() && resolve_commit(repo, name).is_some())
}

fn resolve_commit<'r>(repo: &'r gix::Repository, revision: &str) -> Option<gix::Id<'r>> {
    // A leading dash would be read as an option.
    if revision.starts_with('-') {
        return None;
    }
    let id = repo.rev_parse_single(revision).ok()?;
    let commit = id.object().ok()?.peel_to_commit().ok()?;
    Some(commit.id())
}

fn to_commit(commit: &gix::Commit<'_>) -> Option<Commit> {
    let time = commit.time().ok()?;
    let message = commit.message_raw().ok()?;
    let subject = message.lines().next().unwrap_or_default().to_str_lossy().into_owned();
    Some(Commit { sha: commit.id().to_string(), subject, date: time.seconds as f64 })
}

/// The merge-base rather than `ref` itself, so that commits other people pushed
/// to a moved upstream do not show up as changes made here. `None` when `ref`
/// names nothing, or shares no history with `HEAD`.
pub fn merge_base(path: &str, reference: &str) -> Option<String> {
    let (_, repo) = open(path)?;
    merge_base_of(&repo, reference)
}

fn merge_base_of(repo: &gix::Repository, reference: &str) -> Option<String> {
    let other = resolve_commit(repo, reference)?;
    let head = repo.head_id().ok()?;
    let base = repo.merge_base(head.detach(), other.detach()).ok()??;
    Some(base.to_string())
}

/// What the checked-out branch tracks, such as `origin/main`, or the default
/// branch when it tracks nothing.
pub fn upstream(path: &str) -> Option<String> {
    let (_, repo) = open(path)?;
    let tracked = repo.head_ref().ok().flatten().and_then(|head| {
        let name = repo
            .branch_remote_tracking_ref_name(head.name(), gix::remote::Direction::Fetch)?
            .ok()?;
        // It has to exist: git answers nothing for a tracking branch never fetched.
        repo.try_find_reference(name.as_ref()).ok().flatten()?;
        Some(name.shorten().to_string())
    });
    tracked.or_else(|| default_branch(&repo))
}

/// Lines changed since the working tree forked from the default branch:
/// committed and uncommitted changes to tracked files alike.
pub fn change_summary(path: &str) -> Result<Option<ChangeSummary>, GitError> {
    let Some((root, repo)) = open(path) else { return Ok(None) };
    let Some(fork) = default_branch(&repo).and_then(|base| merge_base_of(&repo, &base)) else {
        return Ok(None);
    };
    super::diff::shortstat(&root, &fork)
}

pub fn shortstat(path: &str, since: &str) -> Result<Option<ChangeSummary>, GitError> {
    match open(path) {
        Some((root, _)) => super::diff::shortstat(&root, since),
        None => Ok(None),
    }
}

pub fn changed_files(
    path: &str,
    since: &str,
) -> Result<Vec<crate::protocol::ChangedFile>, GitError> {
    match open(path) {
        Some((root, _)) => super::diff::changed_files(&root, since),
        None => Ok(Vec::new()),
    }
}

/// Local branches, remote branches and tags, newest tip first.
pub fn refs(path: &str) -> Result<Vec<Ref>, GitError> {
    let Some((_, repo)) = open(path) else { return Ok(Vec::new()) };
    let platform = repo.references().map_err(failed)?;
    let mut refs = Vec::new();
    for reference in platform.all().map_err(failed)?.filter_map(Result::ok) {
        let full = reference.name().as_bstr().to_str_lossy().into_owned();
        let (kind, name) = if let Some(name) = full.strip_prefix("refs/heads/") {
            (RefKind::Branch, name)
        } else if let Some(name) = full.strip_prefix("refs/remotes/") {
            // A remote's own `HEAD` pointer names a branch that is listed already.
            if name.ends_with("/HEAD") {
                continue;
            }
            (RefKind::RemoteBranch, name)
        } else if let Some(name) = full.strip_prefix("refs/tags/") {
            (RefKind::Tag, name)
        } else {
            continue;
        };
        let mut reference = reference;
        // Peeled, so an annotated tag is dated by the commit it points at.
        let date = reference
            .peel_to_commit()
            .ok()
            .and_then(|commit| commit.time().ok())
            .map_or(0.0, |time| time.seconds as f64);
        refs.push(Ref { name: name.to_string(), kind, date });
    }
    refs.sort_by(|a, b| b.date.total_cmp(&a.date).then_with(|| a.name.cmp(&b.name)));
    Ok(refs)
}

/// The `limit` most recent commits reachable from `HEAD`. None for a
/// repository with no commit yet.
pub fn recent_commits(path: &str, limit: usize) -> Result<Vec<Commit>, GitError> {
    let Some((_, repo)) = open(path) else { return Ok(Vec::new()) };
    let Ok(head) = repo.head_id() else { return Ok(Vec::new()) };
    let walk = head
        .ancestors()
        .sorting(gix::revision::walk::Sorting::ByCommitTime(
            gix::traverse::commit::simple::CommitTimeOrder::NewestFirst,
        ))
        .all()
        .map_err(failed)?;
    let mut commits = Vec::new();
    for info in walk.take(limit) {
        let Ok(info) = info else { break };
        if let Some(commit) = info.object().ok().as_ref().and_then(to_commit) {
            commits.push(commit);
        }
    }
    Ok(commits)
}

/// The commit `revision` names, for a SHA or an abbreviation of one.
pub fn commit(path: &str, revision: &str) -> Option<Commit> {
    let (_, repo) = open(path)?;
    let id = resolve_commit(&repo, revision)?;
    to_commit(&id.object().ok()?.into_commit())
}

/// What `file` contained at `revision`: its text exactly as committed, not what
/// the working tree or the index has. `None` when the file is not there, or is
/// not UTF-8: a lossy decode would show every line of such a file as changed.
pub fn contents(path: &str, file: &str, revision: &str) -> Option<String> {
    let (root, repo) = open(path)?;
    let relative = relative_to(&root, Path::new(file))?;
    if revision.starts_with('-') {
        return None;
    }
    let tree = repo.rev_parse_single(revision).ok()?.object().ok()?.peel_to_tree().ok()?;
    let entry = tree.lookup_entry_by_path(&relative).ok()??;
    let object = entry.object().ok()?;
    if object.kind != gix::object::Kind::Blob {
        return None;
    }
    String::from_utf8(object.data.clone()).ok()
}

/// `file` below `root`, as a `/`-separated relative path. The file may no longer
/// exist, so the deepest part that does is resolved and the rest appended.
fn relative_to(root: &Path, file: &Path) -> Option<PathBuf> {
    let mut missing = Vec::new();
    let mut current = file.to_path_buf();
    let resolved = loop {
        if let Ok(resolved) = std::fs::canonicalize(&current) {
            break resolved;
        }
        missing.push(current.file_name()?.to_owned());
        current = current.parent()?.to_path_buf();
    };
    let full = missing.iter().rev().fold(resolved, |path, name| path.join(name));
    let relative = full.strip_prefix(root).ok()?.to_path_buf();
    (!relative.as_os_str().is_empty()).then_some(relative)
}
