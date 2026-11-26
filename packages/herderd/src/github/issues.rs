//! A repository's open issues, and one issue in full.
//!
//! The list is asked for when the app opens "From issue" or refreshes it, never
//! ahead of time. What GitHub last said is kept in memory, by repository, tab
//! and signed-in user, so the modal can show it while a fresh answer is on its
//! way. It is dropped when the token is cleared or replaced and is never
//! written anywhere. An issue's body and comments are not kept at all: an agent
//! starts from what the issue says now.

use super::GitHub;
use crate::git::remote::github_repository;
use crate::protocol::{
    Issue, IssueComment, IssueDetailReply, IssueDetails, IssueFreshness, IssueLabel, IssueList,
    IssueRepoStatus, IssueTab, Secret,
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};

/// How many issues are read per tab.
const PER_TAB: u32 = 50;
/// How many comments are read of one issue, the most recent of them.
const COMMENTS: u32 = 50;

/// What the daemon remembers between questions.
#[derive(Default)]
pub(super) struct State {
    /// Who the token belongs to, once GitHub has said.
    login: Option<String>,
    lists: HashMap<(String, String, IssueTab), Remembered>,
}

impl State {
    /// Forgets the user and everything remembered for them.
    pub(super) fn clear(&mut self) {
        *self = State::default();
    }
}

#[derive(Clone)]
struct Remembered {
    issues: Vec<Issue>,
    fetched_at: f64,
    assigned_count: u64,
    open_count: u64,
}

/// A repository the app asked about, resolved from its `origin`.
struct Target {
    /// `owner/name`, as `origin` spells it.
    repository: String,
    owner: String,
    name: String,
}

enum Fetched {
    Found {
        issues: Vec<Issue>,
        assigned_count: u64,
        open_count: u64,
    },
    Status(IssueRepoStatus),
}

impl GitHub {
    /// Answers an issue query. Blocking, so the caller runs it on a worker.
    pub fn issues(&self, path: &str, tab: IssueTab, freshness: IssueFreshness) -> IssueList {
        let Some(target) = target(path) else {
            return IssueList {
                repository: None,
                status: IssueRepoStatus::Error {
                    message: "not a GitHub repository".into(),
                },
                issues: Vec::new(),
                fetched_at: None,
                assigned_count: None,
                open_count: None,
            };
        };
        let key = target.repository.to_ascii_lowercase();
        let answer = |status| IssueList {
            repository: Some(target.repository.clone()),
            status,
            issues: Vec::new(),
            fetched_at: None,
            assigned_count: None,
            open_count: None,
        };

        let Some(token) = self.held_token() else {
            return answer(IssueRepoStatus::Unauthorized);
        };

        if freshness == IssueFreshness::Cached {
            let state = self.issue_state();
            let remembered = state
                .login
                .as_ref()
                .and_then(|login| state.lists.get(&(login.clone(), key, tab)))
                .cloned();
            return match remembered {
                Some(remembered) => from_memory(&target, remembered),
                None => answer(IssueRepoStatus::Ok),
            };
        }

        let login = match self.login(&token) {
            Ok(login) => login,
            Err(status) => return answer(status),
        };
        match self.fetch_list(&token, &target, &login, tab) {
            Fetched::Status(status) => {
                if status == IssueRepoStatus::Unauthorized {
                    self.issue_state().login = None;
                }
                answer(status)
            }
            Fetched::Found {
                issues,
                assigned_count,
                open_count,
            } => {
                let remembered = Remembered {
                    issues,
                    fetched_at: now(),
                    assigned_count,
                    open_count,
                };
                // A token that has since been replaced is not the user this
                // was asked for, so nothing is kept for it.
                if self.held_token().as_ref() == Some(&token) {
                    let mut state = self.issue_state();
                    if state.login.as_deref().is_some_and(|known| known != login) {
                        state.clear();
                    }
                    state.login = Some(login.clone());
                    state.lists.insert((login, key, tab), remembered.clone());
                }
                from_memory(&target, remembered)
            }
        }
    }

    /// Answers a request for one issue, fresh from GitHub. Blocking.
    pub fn issue_detail(&self, path: &str, number: u64) -> IssueDetailReply {
        let reply = |status, detail| IssueDetailReply { status, detail };
        let Some(target) = target(path) else {
            let message = "not a GitHub repository".to_string();
            return reply(IssueRepoStatus::Error { message }, None);
        };
        let Some(token) = self.held_token() else {
            return reply(IssueRepoStatus::Unauthorized, None);
        };

        let query = "query($o: String!, $n: String!, $number: Int!) { \
            repository(owner: $o, name: $n) { issue(number: $number) { \
            number url title body createdAt updatedAt author { login } \
            labels(first: 20) { nodes { name color } } \
            comments(last: $last) { totalCount nodes { author { login } body createdAt } } \
            } } }"
            .replace("$last", &COMMENTS.to_string());
        let variables = json!({ "o": target.owner, "n": target.name, "number": number });
        let data = match self.graphql::<DetailData>(&token, &query, variables) {
            Ok((data, _)) => data,
            Err(status) => return reply(status, None),
        };
        match data.repository {
            None => reply(IssueRepoStatus::NotAccessible, None),
            Some(RepositoryDetail { issue: Some(node) }) => {
                let comments = node
                    .comments
                    .nodes
                    .iter()
                    .map(|comment| IssueComment {
                        author: comment.author.as_ref().map(|author| author.login.clone()),
                        body: comment.body.clone(),
                        created_at: comment.created_at.clone(),
                    })
                    .collect();
                let body = node.body.clone().unwrap_or_default();
                let detail = IssueDetails {
                    issue: node.into_issue(),
                    body,
                    comments,
                };
                reply(IssueRepoStatus::Ok, Some(detail))
            }
            // No such issue; a pull request's number answers the same.
            Some(RepositoryDetail { issue: None }) => reply(IssueRepoStatus::Ok, None),
        }
    }

    fn held_token(&self) -> Option<Secret> {
        self.token.lock().ok().and_then(|held| held.clone())
    }

    pub(super) fn issue_state(&self) -> std::sync::MutexGuard<'_, State> {
        match self.issues.lock() {
            Ok(state) => state,
            Err(poisoned) => poisoned.into_inner(),
        }
    }

    /// Who the token belongs to: remembered, or asked of GitHub.
    fn login(&self, token: &Secret) -> Result<String, IssueRepoStatus> {
        if let Some(login) = self.issue_state().login.clone() {
            return Ok(login);
        }
        match self.check() {
            crate::protocol::GitHubCheck::Ok { login } => Ok(login),
            crate::protocol::GitHubCheck::NotConnected
            | crate::protocol::GitHubCheck::Unauthorized => Err(IssueRepoStatus::Unauthorized),
            crate::protocol::GitHubCheck::Error { message } => Err(IssueRepoStatus::Error {
                message: scrub(token, message),
            }),
        }
    }

    fn fetch_list(&self, token: &Secret, target: &Target, login: &str, tab: IssueTab) -> Fetched {
        let listed = format!(
            "states: OPEN, first: {PER_TAB}, orderBy: {{field: UPDATED_AT, direction: DESC}}"
        );
        let nodes = "nodes { number url title createdAt updatedAt author { login } \
            labels(first: 10) { nodes { name color } } comments { totalCount } }";
        let query = format!(
            "query($o: String!, $n: String!, $login: String!) {{ \
             repository(owner: $o, name: $n) {{ \
             assigned: issues({listed}, filterBy: {{assignee: $login}}) {{ totalCount {} }} \
             open: issues({listed}) {{ totalCount {} }} }} }}",
            if tab == IssueTab::Assigned { nodes } else { "" },
            if tab == IssueTab::Open { nodes } else { "" },
        );
        let variables = json!({ "o": target.owner, "n": target.name, "login": login });
        let (data, first_error) = match self.graphql::<ListData>(token, &query, variables) {
            Ok(answered) => answered,
            Err(status) => return Fetched::Status(status),
        };
        let Some(repository) = data.repository else {
            return Fetched::Status(IssueRepoStatus::NotAccessible);
        };
        let (Some(assigned), Some(open)) = (repository.assigned, repository.open) else {
            // Said by GitHub, with the token scrubbed out.
            let message = first_error.unwrap_or_else(|| "GitHub's answer had no issues".into());
            return Fetched::Status(error_status(token, message));
        };
        let (assigned_count, open_count) = (assigned.total, open.total);
        let shown = match tab {
            IssueTab::Assigned => assigned.nodes,
            IssueTab::Open => open.nodes,
        };
        Fetched::Found {
            issues: shown.into_iter().map(Node::into_issue).collect(),
            assigned_count,
            open_count,
        }
    }

    /// One GraphQL request, and what it came to: the data, or the status to
    /// report in its place.
    fn graphql<T: for<'de> Deserialize<'de>>(
        &self,
        token: &Secret,
        query: &str,
        variables: Value,
    ) -> Result<(T, Option<String>), IssueRepoStatus> {
        let response = self
            .agent
            .post(&self.endpoint)
            .header("Authorization", format!("Bearer {}", token.expose()))
            .send_json(json!({ "query": query, "variables": variables }));
        let mut response = match response {
            Ok(response) => response,
            Err(error) => {
                return Err(error_status(
                    token,
                    format!("could not reach GitHub: {error}"),
                ));
            }
        };
        match response.status().as_u16() {
            401 => return Err(IssueRepoStatus::Unauthorized),
            200 => {}
            status => return Err(error_status(token, format!("GitHub answered {status}"))),
        }
        let reply = match response.body_mut().read_json::<Reply<T>>() {
            Ok(reply) => reply,
            Err(_) => {
                let message = "GitHub's answer was not one herderd understands".into();
                return Err(error_status(token, message));
            }
        };

        let errors = reply.errors.unwrap_or_default();
        if errors
            .iter()
            .any(|error| error.kind.as_deref() == Some("RATE_LIMITED"))
        {
            return Err(error_status(
                token,
                "GitHub's rate limit was reached".into(),
            ));
        }
        // A repository the App is installed on, whose installation has not
        // approved issues, is refused rather than hidden.
        // Other refusals, such as an organisation's SAML enforcement, are
        // errors with their own words.
        let forbidden = errors.iter().any(|error| {
            error
                .message
                .contains("Resource not accessible by integration")
        });
        let missing_repository = errors.iter().any(|error| {
            error.kind.as_deref() == Some("NOT_FOUND")
                && error.path.as_ref().is_some_and(|path| path.len() <= 1)
        });
        match reply.data {
            Some(data) if !forbidden => Ok((data, errors.into_iter().next().map(|e| e.message))),
            _ if forbidden => Err(IssueRepoStatus::PermissionMissing),
            // A repository the user cannot see is null beside a NOT_FOUND
            // error, in a response that is otherwise fine.
            _ if missing_repository => Err(IssueRepoStatus::NotAccessible),
            _ => {
                let first = errors.into_iter().next().map(|error| error.message);
                let message = first.unwrap_or_else(|| "GitHub's answer had no data".into());
                Err(error_status(token, message))
            }
        }
    }
}

fn target(path: &str) -> Option<Target> {
    let (owner, name) = github_repository(path)?;
    Some(Target {
        repository: format!("{owner}/{name}"),
        owner,
        name,
    })
}

fn from_memory(target: &Target, remembered: Remembered) -> IssueList {
    IssueList {
        repository: Some(target.repository.clone()),
        status: IssueRepoStatus::Ok,
        issues: remembered.issues,
        fetched_at: Some(remembered.fetched_at),
        assigned_count: Some(remembered.assigned_count),
        open_count: Some(remembered.open_count),
    }
}

fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0.0, |elapsed| elapsed.as_secs_f64())
}

/// A failure, with the token scrubbed out of what it says: this text reaches
/// the app's screen.
fn error_status(token: &Secret, message: String) -> IssueRepoStatus {
    IssueRepoStatus::Error {
        message: scrub(token, message),
    }
}

fn scrub(token: &Secret, message: String) -> String {
    // Replacing nothing would put the marker between every character.
    if token.expose().is_empty() {
        return message;
    }
    message.replace(token.expose(), "<redacted>")
}

#[derive(Deserialize)]
struct Reply<T> {
    data: Option<T>,
    errors: Option<Vec<GraphQlError>>,
}

#[derive(Deserialize)]
struct GraphQlError {
    message: String,
    #[serde(rename = "type")]
    kind: Option<String>,
    path: Option<Vec<Value>>,
}

#[derive(Deserialize)]
struct ListData {
    repository: Option<RepositoryList>,
}

#[derive(Deserialize)]
struct RepositoryList {
    assigned: Option<Page>,
    open: Option<Page>,
}

#[derive(Deserialize)]
struct Page {
    #[serde(rename = "totalCount")]
    total: u64,
    #[serde(default)]
    nodes: Vec<Node>,
}

#[derive(Deserialize)]
struct DetailData {
    repository: Option<RepositoryDetail>,
}

#[derive(Deserialize)]
struct RepositoryDetail {
    issue: Option<DetailNode>,
}

#[derive(Deserialize)]
struct Login {
    login: String,
}

#[derive(Deserialize)]
struct Labels {
    nodes: Vec<LabelNode>,
}

#[derive(Deserialize)]
struct LabelNode {
    name: String,
    color: String,
}

#[derive(Deserialize)]
struct Count {
    #[serde(rename = "totalCount")]
    total: u64,
}

#[derive(Deserialize)]
struct Node {
    number: u64,
    url: String,
    title: String,
    #[serde(rename = "createdAt")]
    created_at: String,
    #[serde(rename = "updatedAt")]
    updated_at: String,
    author: Option<Login>,
    labels: Labels,
    comments: Count,
}

impl Node {
    fn into_issue(self) -> Issue {
        Issue {
            number: self.number,
            url: self.url,
            title: self.title,
            labels: self
                .labels
                .nodes
                .into_iter()
                .map(|label| IssueLabel {
                    name: label.name,
                    color: label.color,
                })
                .collect(),
            author: self.author.map(|author| author.login),
            created_at: self.created_at,
            updated_at: self.updated_at,
            comments: self.comments.total,
        }
    }
}

#[derive(Deserialize)]
struct DetailNode {
    number: u64,
    url: String,
    title: String,
    body: Option<String>,
    #[serde(rename = "createdAt")]
    created_at: String,
    #[serde(rename = "updatedAt")]
    updated_at: String,
    author: Option<Login>,
    labels: Labels,
    comments: DetailComments,
}

#[derive(Deserialize)]
struct DetailComments {
    #[serde(rename = "totalCount")]
    total: u64,
    nodes: Vec<CommentNode>,
}

#[derive(Deserialize)]
struct CommentNode {
    author: Option<Login>,
    body: String,
    #[serde(rename = "createdAt")]
    created_at: String,
}

impl DetailNode {
    fn into_issue(self) -> Issue {
        Issue {
            number: self.number,
            url: self.url,
            title: self.title,
            labels: self
                .labels
                .nodes
                .into_iter()
                .map(|label| IssueLabel {
                    name: label.name,
                    color: label.color,
                })
                .collect(),
            author: self.author.map(|author| author.login),
            created_at: self.created_at,
            updated_at: self.updated_at,
            comments: self.comments.total,
        }
    }
}
