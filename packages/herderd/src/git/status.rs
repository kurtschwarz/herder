//! What git says about every path in a working tree, in one pass.
//!
//! Asks git's own machinery rather than reading `.gitignore` files, so nested
//! ignore files, negated patterns and the repository's exclude file all count.
//! An untracked or ignored folder is one entry and nothing below it, unless
//! something in it has a different status than the folder (a nested ignore file
//! can make one file ignored inside an untracked folder).

use super::kind::{self, Opened, canonical};
use crate::protocol::{
    Change, GitError, GitErrorCode, GitResult, PathStatus, RepositoryKind, StatusEntry,
};
use gix::status::{Item, index_worktree};
use std::collections::BTreeMap;

fn failed(error: impl std::fmt::Display) -> GitError {
    GitError { code: GitErrorCode::Failed, message: error.to_string() }
}

/// Both columns of a tracked path, filled in from whichever side reports it.
#[derive(Default)]
struct Columns {
    staged: Option<Change>,
    unstaged: Option<Change>,
    unmerged: bool,
}

pub fn status(path: &str) -> Result<GitResult, GitError> {
    let Some(Opened { repo, kind }) = kind::open(path) else {
        return Ok(empty(path));
    };
    if !matches!(kind, RepositoryKind::MainWorkingTree | RepositoryKind::LinkedWorktree { .. }) {
        return Ok(empty(path));
    }
    let root = kind::path_string(&canonical(repo.workdir().unwrap_or(repo.git_dir())));

    let mut tracked: BTreeMap<String, Columns> = BTreeMap::new();
    let mut others: BTreeMap<String, PathStatus> = BTreeMap::new();

    let items = repo
        .status(gix::progress::Discard)
        .map_err(failed)?
        .untracked_files(gix::status::UntrackedFiles::Collapsed)
        .dirwalk_options(|options| {
            options
                .emit_ignored(Some(gix::dir::walk::EmissionMode::Matching))
                // What `git status --ignored=matching` shows: an ignored file
                // inside an untracked folder is still reported.
                .emit_collapsed(Some(
                    gix::dir::walk::CollapsedEntriesEmissionMode::OnStatusMismatch,
                ))
        })
        .into_iter(None)
        .map_err(failed)?;

    for item in items {
        match item.map_err(failed)? {
            Item::TreeIndex(change) => {
                use gix::diff::index::Change as Staged;
                match change {
                    Staged::Addition { location, .. } => {
                        tracked.entry(text(&location[..])).or_default().staged =
                            Some(Change::Added);
                    }
                    Staged::Deletion { location, .. } => {
                        tracked.entry(text(&location[..])).or_default().staged =
                            Some(Change::Deleted);
                    }
                    Staged::Modification { location, previous_entry_mode, entry_mode, .. } => {
                        let kind_changed =
                            previous_entry_mode.to_tree_entry_mode().map(|m| m.kind())
                                != entry_mode.to_tree_entry_mode().map(|m| m.kind());
                        tracked.entry(text(&location[..])).or_default().staged =
                            Some(if kind_changed { Change::TypeChanged } else { Change::Modified });
                    }
                    Staged::Rewrite { source_location, location, copy, .. } => {
                        let change = if copy { Change::Copied } else { Change::Renamed };
                        tracked.entry(text(&location[..])).or_default().staged = Some(change);
                        // The path it came from is recorded too: a folder a file
                        // moved out of is a folder something changed in, and
                        // nothing else in the output would say so.
                        if !copy {
                            tracked.entry(text(&source_location[..])).or_default().staged =
                                Some(Change::Renamed);
                        }
                    }
                }
            }
            Item::IndexWorktree(item) => match item {
                index_worktree::Item::Modification { rela_path, status, .. } => {
                    use gix::status::plumbing::index_as_worktree::{
                        Change as Worktree, EntryStatus,
                    };
                    let columns = tracked.entry(text(&rela_path[..])).or_default();
                    match status {
                        EntryStatus::Conflict { .. } => columns.unmerged = true,
                        EntryStatus::Change(Worktree::Removed) => {
                            columns.unstaged = Some(Change::Deleted)
                        }
                        EntryStatus::Change(Worktree::Type { .. }) => {
                            columns.unstaged = Some(Change::TypeChanged)
                        }
                        EntryStatus::Change(_) => columns.unstaged = Some(Change::Modified),
                        EntryStatus::IntentToAdd => columns.unstaged = Some(Change::Added),
                        EntryStatus::NeedsUpdate(_) => {}
                    }
                }
                index_worktree::Item::DirectoryContents { entry, .. } => {
                    use gix::dir::entry::Status;
                    let path = text(&entry.rela_path[..]);
                    match entry.status {
                        Status::Untracked => {
                            others.insert(path, PathStatus::Untracked);
                        }
                        Status::Ignored(_) => {
                            others.insert(path, PathStatus::Ignored);
                        }
                        Status::Tracked | Status::Pruned => {}
                    }
                }
                index_worktree::Item::Rewrite { source, dirwalk_entry, .. } => {
                    tracked.entry(text(&dirwalk_entry.rela_path[..])).or_default().unstaged =
                        Some(Change::Renamed);
                    tracked.entry(text(source.rela_path())).or_default().unstaged =
                        Some(Change::Deleted);
                }
            },
        }
    }

    let mut entries: Vec<StatusEntry> =
        others.into_iter().map(|(path, status)| StatusEntry { path, status }).collect();
    for (path, columns) in tracked {
        let status = if columns.unmerged {
            PathStatus::Unmerged
        } else {
            PathStatus::Tracked {
                staged: columns.staged.unwrap_or(Change::Unchanged),
                unstaged: columns.unstaged.unwrap_or(Change::Unchanged),
            }
        };
        entries.push(StatusEntry { path, status });
    }
    Ok(GitResult::Status { root, entries })
}

fn empty(path: &str) -> GitResult {
    GitResult::Status {
        root: kind::path_string(&canonical(std::path::Path::new(path))),
        entries: Vec::new(),
    }
}

fn text(path: &[u8]) -> String {
    String::from_utf8_lossy(path).into_owned()
}
