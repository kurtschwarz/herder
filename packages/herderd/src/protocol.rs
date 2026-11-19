//! The messages of the first exchange, and the rules for choosing a version.
//!
//! Payloads are JSON, tagged by `type`. The first frame on every connection is
//! the client's [`ClientMessage::Hello`]; nothing else is accepted until the
//! daemon has answered it. Later versions add messages and fields and never
//! change the meaning of one, which is what lets a newer app talk to an older
//! daemon that is still holding sessions.

use serde::{Deserialize, Serialize};

/// The oldest protocol version this build speaks.
///
/// 2 is the version that added git. Raised together with [`MAX_PROTOCOL`]
/// because nothing used the daemon before it, so there is no older app to keep
/// serving.
pub const MIN_PROTOCOL: u32 = 2;
/// The newest protocol version this build speaks.
pub const MAX_PROTOCOL: u32 = 2;

/// Which machine a record belongs to. Every session and worktree the protocol
/// names carries one, so a second host later is not a migration of the keys
/// anything persisted under.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct HostId(pub String);

impl HostId {
    /// The machine the daemon is running on, as seen from the app that
    /// started it.
    pub fn local() -> Self {
        HostId("local".to_string())
    }
}

#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientMessage {
    Hello {
        /// The range of versions the client can speak.
        min_protocol: u32,
        max_protocol: u32,
        /// Who is asking, for the daemon's log: "Herder 0.3.3".
        client: String,
    },
    /// Asks for one git operation. The answer is a [`DaemonMessage::GitResponse`]
    /// with the same `id`.
    GitRequest {
        id: u64,
        #[serde(flatten)]
        op: GitOp,
    },
}

/// A git operation and its arguments. Paths are strings on the daemon's host,
/// never the app's idea of one.
#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum GitOp {
    RepositoryKind {
        path: String,
    },
    Worktrees {
        path: String,
    },
    Branches {
        path: String,
    },
    GitDirectory {
        path: String,
    },
    Checkout {
        path: String,
    },
    Status {
        path: String,
    },
    ChangeSummary {
        path: String,
    },
    MergeBase {
        path: String,
        #[serde(rename = "ref")]
        reference: String,
    },
    Upstream {
        path: String,
    },
    Shortstat {
        path: String,
        since: String,
    },
    ChangedFiles {
        path: String,
        since: String,
    },
    Refs {
        path: String,
    },
    RecentCommits {
        path: String,
        limit: usize,
    },
    Commit {
        path: String,
        revision: String,
    },
    /// `file` is a path on the host, which must lie inside the working tree.
    Contents {
        path: String,
        file: String,
        revision: String,
    },
    /// Adds a working tree at `worktree` on a new branch cut from `base`. When
    /// `exclude` names a folder directly inside the repository, it is added to
    /// `.git/info/exclude` first so the new tree does not show as untracked.
    AddWorktree {
        path: String,
        worktree: String,
        new_branch: String,
        base: String,
        exclude: Option<String>,
    },
}

/// What a working tree has checked out.
#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Checkout {
    Branch {
        name: String,
    },
    /// `sha` is the first seven characters of the commit.
    Detached {
        sha: String,
    },
}

/// One column of git's two-letter status code.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Change {
    Unchanged,
    Added,
    Modified,
    Deleted,
    Renamed,
    Copied,
    TypeChanged,
}

/// What git knows about one path.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum PathStatus {
    Tracked { staged: Change, unstaged: Change },
    Unmerged,
    Untracked,
    Ignored,
}

/// A path under the working tree's root, and what git says about it.
#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct StatusEntry {
    pub path: String,
    pub status: PathStatus,
}

/// Lines inserted and deleted.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChangeSummary {
    pub insertions: u64,
    pub deletions: u64,
}

/// How a tracked file differs from a revision.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FileChange {
    Modified,
    Added,
    Deleted,
    Renamed,
}

#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChangedFile {
    /// Relative to the working tree, with `/` separators.
    pub path: String,
    /// Where a renamed file was.
    pub previous_path: Option<String>,
    pub status: FileChange,
    pub insertions: u64,
    pub deletions: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RefKind {
    Branch,
    RemoteBranch,
    Tag,
}

/// A branch or tag, with when its tip was committed.
#[derive(Debug, PartialEq, Serialize, Deserialize)]
pub struct Ref {
    /// The short name: `main`, `origin/main`, `v1.2`.
    pub name: String,
    pub kind: RefKind,
    /// Seconds since the Unix epoch.
    pub date: f64,
}

#[derive(Debug, PartialEq, Serialize, Deserialize)]
pub struct Commit {
    pub sha: String,
    pub subject: String,
    /// Seconds since the Unix epoch.
    pub date: f64,
}

/// One working tree of a repository, in the order the sidebar shows them.
#[derive(Debug, PartialEq, Serialize, Deserialize)]
pub struct Worktree {
    pub host: HostId,
    pub path: String,
    pub checkout: Checkout,
    pub is_main_working_tree: bool,
    /// Seconds since the Unix epoch, from the reflog.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub last_activity: Option<f64>,
}

/// What a folder is, as far as git is concerned.
#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum RepositoryKind {
    MainWorkingTree,
    Bare,
    LinkedWorktree { main_repository: String },
    NotARepository,
}

/// The answer to a [`GitOp`], shaped per operation.
#[derive(Debug, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum GitResult {
    RepositoryKind(RepositoryKind),
    Worktrees {
        worktrees: Vec<Worktree>,
    },
    Branches {
        branches: Vec<String>,
    },
    /// `null` for a folder that is not a working tree.
    GitDirectory {
        path: Option<String>,
    },
    /// `null` for a folder that is not a working tree, or whose `HEAD` cannot
    /// be read.
    Checkout {
        checkout: Option<Checkout>,
    },
    /// `root` is the working tree, resolved; each entry's `path` is relative to
    /// it. No entries for a folder that is not a working tree.
    Status {
        root: String,
        entries: Vec<StatusEntry>,
    },
    /// `null` for a folder that is not a working tree, or when git cannot say.
    Summary {
        summary: Option<ChangeSummary>,
    },
    /// `null` when the ref names nothing, or shares no history with `HEAD`.
    MergeBase {
        sha: Option<String>,
    },
    Upstream {
        upstream: Option<String>,
    },
    ChangedFiles {
        files: Vec<ChangedFile>,
    },
    Refs {
        refs: Vec<Ref>,
    },
    Commits {
        commits: Vec<Commit>,
    },
    Commit {
        commit: Option<Commit>,
    },
    /// `null` when the file is not in that revision, or is not UTF-8.
    Contents {
        text: Option<String>,
    },
    AddedWorktree {
        worktree: String,
    },
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GitErrorCode {
    /// Git ran, or could have, and refused.
    Failed,
    /// The request itself was not one the daemon could act on.
    InvalidRequest,
}

#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct GitError {
    pub code: GitErrorCode,
    pub message: String,
}

#[derive(Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum DaemonMessage {
    /// The daemon spoke first-contact and the two sides share a version.
    Welcome {
        /// The version every later message on this connection uses.
        protocol: u32,
        daemon_version: String,
        host: HostId,
    },
    /// No version in common. The connection closes after this, and the
    /// ranges are what the app shows the user.
    Incompatible { min_protocol: u32, max_protocol: u32, daemon_version: String },
    /// The outcome of a [`ClientMessage::GitRequest`]: exactly one of `result`
    /// and `error`.
    GitResponse {
        id: u64,
        #[serde(skip_serializing_if = "Option::is_none")]
        result: Option<GitResult>,
        #[serde(skip_serializing_if = "Option::is_none")]
        error: Option<GitError>,
    },
}

/// The highest version both sides speak, if there is one.
pub fn negotiate(client_min: u32, client_max: u32) -> Option<u32> {
    let highest = client_max.min(MAX_PROTOCOL);
    let lowest = client_min.max(MIN_PROTOCOL);
    (lowest <= highest).then_some(highest)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn picks_the_highest_shared_version() {
        assert_eq!(negotiate(MAX_PROTOCOL, MAX_PROTOCOL), Some(MAX_PROTOCOL));
        assert_eq!(negotiate(1, 9), Some(MAX_PROTOCOL));
        assert_eq!(negotiate(0, MAX_PROTOCOL), Some(MAX_PROTOCOL));
    }

    #[test]
    fn no_overlap_is_no_version() {
        assert_eq!(negotiate(MAX_PROTOCOL + 1, MAX_PROTOCOL + 3), None);
        assert_eq!(negotiate(0, MIN_PROTOCOL - 1), None);
    }

    #[test]
    fn hello_is_tagged_json() {
        let hello = ClientMessage::Hello { min_protocol: 1, max_protocol: 2, client: "t".into() };
        let json = serde_json::to_string(&hello).unwrap();
        assert_eq!(json, r#"{"type":"hello","min_protocol":1,"max_protocol":2,"client":"t"}"#);
    }

    #[test]
    fn welcome_carries_the_host() {
        let welcome = DaemonMessage::Welcome {
            protocol: 2,
            daemon_version: "0.1.0".into(),
            host: HostId::local(),
        };
        let json = serde_json::to_string(&welcome).unwrap();
        assert_eq!(
            json,
            r#"{"type":"welcome","protocol":2,"daemon_version":"0.1.0","host":"local"}"#
        );
    }

    #[test]
    fn a_git_request_is_one_flat_object() {
        let request =
            ClientMessage::GitRequest { id: 7, op: GitOp::RepositoryKind { path: "/r".into() } };
        let json = serde_json::to_string(&request).unwrap();
        assert_eq!(json, r#"{"type":"git_request","id":7,"op":"repository_kind","path":"/r"}"#);
        assert_eq!(serde_json::from_str::<ClientMessage>(&json).unwrap(), request);
    }

    #[test]
    fn a_git_response_holds_a_result_or_an_error() {
        let ok = DaemonMessage::GitResponse {
            id: 7,
            result: Some(GitResult::RepositoryKind(RepositoryKind::LinkedWorktree {
                main_repository: "/r".into(),
            })),
            error: None,
        };
        assert_eq!(
            serde_json::to_string(&ok).unwrap(),
            r#"{"type":"git_response","id":7,"result":{"kind":"linked_worktree","main_repository":"/r"}}"#
        );

        let failed = DaemonMessage::GitResponse {
            id: 8,
            result: None,
            error: Some(GitError { code: GitErrorCode::Failed, message: "no".into() }),
        };
        assert_eq!(
            serde_json::to_string(&failed).unwrap(),
            r#"{"type":"git_response","id":8,"error":{"code":"failed","message":"no"}}"#
        );
    }
}
