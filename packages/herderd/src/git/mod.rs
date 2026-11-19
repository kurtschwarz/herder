//! Every git operation the app asks the daemon for.
//!
//! Portable: this reads repositories with `gix` and takes host-relative path
//! strings, so it behaves the same on a remote host as on this one. Where
//! `gix` cannot match what `git` prints, the one operation calls the CLI
//! through [`cli`], and each such operation is listed there.

pub mod cli;
mod diff;
mod history;
mod kind;
mod layout;
mod natural;
mod status;

use crate::protocol::{GitError, GitOp, GitResult};

/// Answers one request. Blocking, so the caller runs it on a worker.
pub fn handle(op: &GitOp) -> Result<GitResult, GitError> {
    match op {
        GitOp::RepositoryKind { path } => {
            Ok(GitResult::RepositoryKind(kind::repository_kind(path)))
        }
        GitOp::Worktrees { path } => {
            layout::worktrees(path).map(|worktrees| GitResult::Worktrees { worktrees })
        }
        GitOp::Branches { path } => {
            layout::branches(path).map(|branches| GitResult::Branches { branches })
        }
        GitOp::GitDirectory { path } => {
            Ok(GitResult::GitDirectory { path: layout::git_directory(path) })
        }
        GitOp::Status { path } => status::status(path),
        GitOp::ChangeSummary { path } => {
            history::change_summary(path).map(|summary| GitResult::Summary { summary })
        }
        GitOp::MergeBase { path, reference } => {
            Ok(GitResult::MergeBase { sha: history::merge_base(path, reference) })
        }
        GitOp::Upstream { path } => Ok(GitResult::Upstream { upstream: history::upstream(path) }),
        GitOp::Shortstat { path, since } => {
            history::shortstat(path, since).map(|summary| GitResult::Summary { summary })
        }
        GitOp::ChangedFiles { path, since } => {
            history::changed_files(path, since).map(|files| GitResult::ChangedFiles { files })
        }
        GitOp::Refs { path } => history::refs(path).map(|refs| GitResult::Refs { refs }),
        GitOp::RecentCommits { path, limit } => {
            history::recent_commits(path, *limit).map(|commits| GitResult::Commits { commits })
        }
        GitOp::Commit { path, revision } => {
            Ok(GitResult::Commit { commit: history::commit(path, revision) })
        }
        GitOp::Contents { path, file, revision } => {
            Ok(GitResult::Contents { text: history::contents(path, file, revision) })
        }
        GitOp::Checkout { path } => Ok(GitResult::Checkout { checkout: layout::checkout(path) }),
    }
}
