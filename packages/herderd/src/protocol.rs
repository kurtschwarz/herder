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
/// The newest protocol version this build speaks. 3 added the GitHub token and
/// 4 added pull request queries. Nothing in either changes a message of 2, so
/// an app that speaks 2 is still served.
pub const MAX_PROTOCOL: u32 = 4;

/// A credential. Its `Debug` never shows the value, so a message that carries
/// one can be logged, printed in a panic or put in an error without leaking it.
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct Secret(String);

impl Secret {
    pub fn new(value: impl Into<String>) -> Self {
        Secret(value.into())
    }

    /// The credential itself. Only the code that sends it to GitHub calls this.
    pub fn expose(&self) -> &str {
        &self.0
    }
}

impl std::fmt::Debug for Secret {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("Secret(<redacted>)")
    }
}

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
    /// Hands the daemon the GitHub access token to use from now on, replacing
    /// any it holds. It is kept in memory only. The answer is a
    /// [`DaemonMessage::GitHubResponse`] saying whether it works. Added in
    /// protocol 3.
    #[serde(rename = "set_github_token")]
    SetGitHubToken { id: u64, token: Secret },
    /// Makes the daemon forget its GitHub token. Added in protocol 3.
    #[serde(rename = "clear_github_token")]
    ClearGitHubToken { id: u64 },
    /// Asks whether the token the daemon holds works, without changing it.
    /// Added in protocol 3.
    #[serde(rename = "check_github")]
    CheckGitHub { id: u64 },
    /// Asks for the newest pull request of each branch, in one request to
    /// GitHub however many repositories and branches there are. The answer is
    /// a [`DaemonMessage::PullRequestResponse`]. Added in protocol 4.
    #[serde(rename = "pull_request_query")]
    PullRequestQuery { id: u64, repos: Vec<PullRequestRepo> },
}

/// A repository to ask about, and the branches of it to look for pull
/// requests from. `path` is a folder on the daemon's host; the GitHub
/// repository is the one its `origin` names.
#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PullRequestRepo {
    pub path: String,
    pub branches: Vec<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PullRequestState {
    Open,
    Merged,
    Closed,
}

/// A pull request, as far as a badge needs it.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PullRequest {
    pub number: u64,
    pub url: String,
    pub title: String,
    pub state: PullRequestState,
    pub is_draft: bool,
    /// ISO 8601, as GitHub gives it.
    pub merged_at: Option<String>,
    pub updated_at: String,
}

/// What asking GitHub about one repository came to. Never quotes the token.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum PullRequestRepoStatus {
    Ok,
    /// The GitHub App is not installed on the repository, or the signed-in
    /// user cannot see it.
    NotAccessible,
    /// GitHub refused the token, or the daemon holds none.
    Unauthorized,
    /// GitHub could not be asked. The branches, when there are any, are what
    /// it last said.
    Error {
        message: String,
    },
}

/// The newest same-repository pull request from one branch, or `None`.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct BranchPullRequest {
    pub branch: String,
    pub pull_request: Option<PullRequest>,
}

/// The answer for one [`PullRequestRepo`], under the same `path`.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RepoPullRequests {
    pub path: String,
    /// `owner/name`, as `origin` names it.
    pub repository: String,
    pub status: PullRequestRepoStatus,
    /// The repository's default branch, once GitHub has said. Nothing is
    /// looked up for it, so the app can leave it out of later queries.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub default_branch: Option<String>,
    pub branches: Vec<BranchPullRequest>,
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

/// What a `viewer` query made with the daemon's GitHub token came to. Never
/// holds the token, and `message` never quotes it.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum GitHubCheck {
    /// The daemon holds no token.
    NotConnected,
    /// The token works, and belongs to `login`.
    Ok { login: String },
    /// GitHub refused the token: it is expired or revoked.
    Unauthorized,
    /// GitHub could not be asked, or its answer was not one the daemon knows.
    Error { message: String },
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
    Incompatible {
        min_protocol: u32,
        max_protocol: u32,
        daemon_version: String,
        /// How many sessions this daemon owns. An app newer than the daemon
        /// ends and replaces it only when this is 0, since ending it ends them.
        /// Added in protocol 2; a daemon that leaves it out speaks only
        /// protocol 1, which had no sessions.
        sessions: u32,
    },
    /// The outcome of a [`ClientMessage::GitRequest`]: exactly one of `result`
    /// and `error`.
    GitResponse {
        id: u64,
        #[serde(skip_serializing_if = "Option::is_none")]
        result: Option<GitResult>,
        #[serde(skip_serializing_if = "Option::is_none")]
        error: Option<GitError>,
    },
    /// The outcome of a GitHub message, with the same `id`. Carries what the
    /// daemon found out, never the token.
    #[serde(rename = "github_response")]
    GitHubResponse { id: u64, check: GitHubCheck },
    /// The outcome of a [`ClientMessage::PullRequestQuery`], with the same
    /// `id`. A repository whose `origin` is not on github.com has no entry.
    /// `next_poll_seconds` is how long the app should wait before asking
    /// again: it grows while GitHub cannot be reached.
    #[serde(rename = "pull_request_response")]
    PullRequestResponse { id: u64, repos: Vec<RepoPullRequests>, next_poll_seconds: u64 },
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
    fn an_app_that_speaks_only_2_is_still_served() {
        assert_eq!(negotiate(2, 2), Some(2));
    }

    #[test]
    fn a_token_is_never_shown_by_debug() {
        let message = ClientMessage::SetGitHubToken { id: 1, token: Secret::new("ghu_hunter2") };
        assert!(!format!("{message:?}").contains("hunter2"));
        assert!(!format!("{:?}", Secret::new("hunter2")).contains("hunter2"));
    }

    #[test]
    fn the_token_messages_are_tagged_json() {
        let set = ClientMessage::SetGitHubToken { id: 4, token: Secret::new("t") };
        let json = serde_json::to_string(&set).unwrap();
        assert_eq!(json, r#"{"type":"set_github_token","id":4,"token":"t"}"#);
        assert_eq!(serde_json::from_str::<ClientMessage>(&json).unwrap(), set);

        let clear = ClientMessage::ClearGitHubToken { id: 5 };
        assert_eq!(
            serde_json::to_string(&clear).unwrap(),
            r#"{"type":"clear_github_token","id":5}"#
        );
    }

    #[test]
    fn a_github_response_names_the_state_and_no_token() {
        let reply = DaemonMessage::GitHubResponse {
            id: 4,
            check: GitHubCheck::Ok { login: "kurt".into() },
        };
        assert_eq!(
            serde_json::to_string(&reply).unwrap(),
            r#"{"type":"github_response","id":4,"check":{"state":"ok","login":"kurt"}}"#
        );
    }

    #[test]
    fn a_pull_request_query_is_tagged_json() {
        let query = ClientMessage::PullRequestQuery {
            id: 2,
            repos: vec![PullRequestRepo { path: "/r".into(), branches: vec!["a".into()] }],
        };
        let json = serde_json::to_string(&query).unwrap();
        assert_eq!(
            json,
            r#"{"type":"pull_request_query","id":2,"repos":[{"path":"/r","branches":["a"]}]}"#
        );
        assert_eq!(serde_json::from_str::<ClientMessage>(&json).unwrap(), query);
    }

    #[test]
    fn a_pull_request_response_names_each_state() {
        let reply = DaemonMessage::PullRequestResponse {
            id: 2,
            next_poll_seconds: 60,
            repos: vec![RepoPullRequests {
                path: "/r".into(),
                repository: "o/r".into(),
                status: PullRequestRepoStatus::Error { message: "no".into() },
                default_branch: None,
                branches: vec![BranchPullRequest {
                    branch: "a".into(),
                    pull_request: Some(PullRequest {
                        number: 3,
                        url: "u".into(),
                        title: "t".into(),
                        state: PullRequestState::Merged,
                        is_draft: false,
                        merged_at: Some("2026-01-01T00:00:00Z".into()),
                        updated_at: "2026-01-01T00:00:00Z".into(),
                    }),
                }],
            }],
        };
        assert_eq!(
            serde_json::to_string(&reply).unwrap(),
            concat!(
                r#"{"type":"pull_request_response","id":2,"repos":[{"path":"/r","repository":"o/r","#,
                r#""status":{"state":"error","message":"no"},"branches":[{"branch":"a","pull_request":"#,
                r#"{"number":3,"url":"u","title":"t","state":"merged","is_draft":false,"#,
                r#""merged_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}}]}],"#,
                r#""next_poll_seconds":60}"#
            )
        );
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
