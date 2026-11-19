//! The newest pull request of every watched branch, in one GraphQL request.
//!
//! The app asks on a timer, because the daemon cannot push yet, and the daemon
//! keeps what GitHub last said in memory only. When GitHub cannot be reached,
//! that is what it answers with, and `next_poll_seconds` doubles up to ten
//! minutes so the app does not keep asking a server that is down. A refused
//! token is not a failure of that kind: the app is told, and refreshes it.

use super::GitHub;
use crate::git::remote::github_repository;
use crate::protocol::{
    BranchPullRequest, PullRequest, PullRequestRepo, PullRequestRepoStatus, PullRequestState,
    RepoPullRequests, Secret,
};
use serde::Deserialize;
use serde_json::{Map, Value, json};
use std::collections::HashMap;

/// How long the app waits between questions while all is well.
const BASE_INTERVAL: u64 = 60;
/// How long it waits at the most, however long GitHub has been failing.
const MAX_INTERVAL: u64 = 600;

/// How many pull requests are read per branch. More than the one wanted, so a
/// fork's pull request from a branch of the same name cannot hide the
/// repository's own: forks are filtered out after.
const PER_BRANCH: u32 = 5;

/// What the daemon remembers between questions.
#[derive(Default)]
pub(super) struct State {
    failures: u32,
    repositories: HashMap<String, Remembered>,
}

/// What GitHub last said of one repository.
#[derive(Default)]
struct Remembered {
    default_branch: Option<String>,
    branches: HashMap<String, Option<PullRequest>>,
}

/// A repository the app asked about, resolved from its `origin`.
struct Target {
    path: String,
    /// `owner/name`, as `origin` spells it.
    repository: String,
    /// What names the repository wherever it is remembered: GitHub does not
    /// tell `Owner/Repo` from `owner/repo`, so neither does this.
    key: String,
    branches: Vec<String>,
}

/// What one request to GitHub came to, repository by repository.
enum Outcome {
    Answered(HashMap<String, Answered>),
    Unauthorized,
    Failed(String),
}

/// A repository to ask about, with every branch any folder of it wants.
struct Watched<'a> {
    key: &'a str,
    name: &'a str,
    branches: Vec<&'a str>,
}

#[derive(Clone)]
enum Answered {
    Found { default_branch: Option<String>, branches: HashMap<String, Option<PullRequest>> },
    NotAccessible,
}

impl GitHub {
    /// Answers a pull request query: one entry for each repository whose
    /// `origin` is on github.com, and how many seconds the app should wait
    /// before asking again. Blocking, so the caller runs it on a worker.
    pub fn pull_requests(&self, asked: &[PullRequestRepo]) -> (Vec<RepoPullRequests>, u64) {
        let targets: Vec<Target> = asked
            .iter()
            .filter_map(|repo| {
                let (owner, name) = github_repository(&repo.path)?;
                let mut branches: Vec<String> = Vec::new();
                for branch in &repo.branches {
                    if !branches.contains(branch) {
                        branches.push(branch.clone());
                    }
                }
                let repository = format!("{owner}/{name}");
                let key = repository.to_ascii_lowercase();
                Some(Target { path: repo.path.clone(), repository, key, branches })
            })
            .collect();
        if targets.is_empty() {
            return (Vec::new(), self.next_poll());
        }

        let token = self.token.lock().ok().and_then(|held| held.clone());
        let outcome = match &token {
            Some(token) => self.ask(token, &targets),
            None => Outcome::Unauthorized,
        };

        let mut state = match self.pull_requests.lock() {
            Ok(state) => state,
            Err(poisoned) => poisoned.into_inner(),
        };
        let mut statuses: HashMap<&str, PullRequestRepoStatus> = HashMap::new();
        match outcome {
            Outcome::Answered(answers) => {
                state.failures = 0;
                for target in &targets {
                    // Cloned, not taken: two folders can be one repository.
                    let status = match answers.get(&target.key).cloned() {
                        Some(Answered::Found { default_branch, branches }) => {
                            let remembered =
                                state.repositories.entry(target.key.clone()).or_default();
                            remembered.default_branch = default_branch;
                            remembered.branches.extend(branches);
                            PullRequestRepoStatus::Ok
                        }
                        Some(Answered::NotAccessible) | None => {
                            state.repositories.remove(&target.key);
                            PullRequestRepoStatus::NotAccessible
                        }
                    };
                    statuses.insert(&target.key, status);
                }
            }
            Outcome::Unauthorized => {
                for target in &targets {
                    statuses.insert(&target.key, PullRequestRepoStatus::Unauthorized);
                }
            }
            Outcome::Failed(message) => {
                state.failures = state.failures.saturating_add(1);
                for target in &targets {
                    let status = PullRequestRepoStatus::Error { message: message.clone() };
                    statuses.insert(&target.key, status);
                }
            }
        }

        let answers = targets
            .iter()
            .map(|target| {
                let remembered = state.repositories.get(&target.key);
                let branches = target
                    .branches
                    .iter()
                    .filter_map(|branch| {
                        let pull_request = remembered?.branches.get(branch)?;
                        Some(BranchPullRequest {
                            branch: branch.clone(),
                            pull_request: pull_request.clone(),
                        })
                    })
                    .collect();
                RepoPullRequests {
                    path: target.path.clone(),
                    repository: target.repository.clone(),
                    status: statuses[target.key.as_str()].clone(),
                    default_branch: remembered.and_then(|known| known.default_branch.clone()),
                    branches,
                }
            })
            .collect();
        let wait = interval(state.failures);
        (answers, wait)
    }

    fn next_poll(&self) -> u64 {
        let failures = self.pull_requests.lock().map_or(0, |state| state.failures);
        interval(failures)
    }

    fn ask(&self, token: &Secret, targets: &[Target]) -> Outcome {
        // One entry per repository however many folders name it.
        let mut repositories: Vec<Watched> = Vec::new();
        for target in targets {
            let index = match repositories.iter().position(|watched| watched.key == target.key) {
                Some(index) => index,
                None => {
                    let (key, name) = (&target.key, &target.repository);
                    repositories.push(Watched { key, name, branches: Vec::new() });
                    repositories.len() - 1
                }
            };
            for branch in &target.branches {
                if !repositories[index].branches.contains(&branch.as_str()) {
                    repositories[index].branches.push(branch);
                }
            }
        }

        let (query, variables) = build(&repositories);
        let response = self
            .agent
            .post(&self.endpoint)
            .header("Authorization", format!("Bearer {}", token.expose()))
            .send_json(json!({ "query": query, "variables": variables }));
        let mut response = match response {
            Ok(response) => response,
            Err(error) => return failed(token, format!("could not reach GitHub: {error}")),
        };

        match response.status().as_u16() {
            401 => return Outcome::Unauthorized,
            200 => {}
            status => return failed(token, format!("GitHub answered {status}")),
        }
        let reply = match response.body_mut().read_json::<Reply>() {
            Ok(reply) => reply,
            Err(_) => {
                return failed(token, "GitHub's answer was not one herderd understands".into());
            }
        };

        let errors = reply.errors.unwrap_or_default();
        if errors.iter().any(|error| error.kind.as_deref() == Some("RATE_LIMITED")) {
            return failed(token, "GitHub's rate limit was reached".into());
        }
        let Some(mut data) = reply.data else {
            let first = errors.into_iter().next().map(|error| error.message);
            return failed(token, first.unwrap_or_else(|| "GitHub's answer had no data".into()));
        };

        let answers = repositories
            .iter()
            .enumerate()
            .map(|(index, Watched { key, name, branches })| {
                // A repository the signed-in user cannot see comes back null,
                // beside a NOT_FOUND error, in a response that is otherwise fine.
                let answered = match data.remove(&format!("r{index}")).flatten() {
                    Some(mut found) => Answered::Found {
                        default_branch: found.default_branch_ref.map(|head| head.name),
                        branches: branches
                            .iter()
                            .enumerate()
                            .map(|(slot, branch)| {
                                let nodes = found
                                    .branches
                                    .remove(&format!("b{slot}"))
                                    .map(|connection| connection.nodes)
                                    .unwrap_or_default();
                                (branch.to_string(), newest(nodes, name))
                            })
                            .collect(),
                    },
                    None => Answered::NotAccessible,
                };
                (key.to_string(), answered)
            })
            .map(|(key, answered)| match answered {
                // The default branch is never looked up for: its pull requests
                // are the ones into other branches' names, not its own work.
                Answered::Found { default_branch: Some(default), mut branches } => {
                    if let Some(entry) = branches.get_mut(&default) {
                        *entry = None;
                    }
                    (key, Answered::Found { default_branch: Some(default), branches })
                }
                other => (key, other),
            })
            .collect();
        Outcome::Answered(answers)
    }
}

/// How long to wait with `failures` in a row: a minute, then doubled each
/// time, up to ten.
fn interval(failures: u32) -> u64 {
    (BASE_INTERVAL << failures.min(10)).min(MAX_INTERVAL)
}

/// A failure, with the token scrubbed out of what it says: this text reaches
/// the app's screen.
fn failed(token: &Secret, message: String) -> Outcome {
    // Replacing nothing would put the marker between every character.
    if token.expose().is_empty() {
        return Outcome::Failed(message);
    }
    Outcome::Failed(message.replace(token.expose(), "<redacted>"))
}

/// The query and its variables. Names and branches are variables, never part
/// of the query text, so a branch called anything cannot change what is asked.
fn build(repositories: &[Watched]) -> (String, Value) {
    let mut declarations = Vec::new();
    let mut selections = Vec::new();
    let mut variables = Map::new();
    for (index, Watched { name: repository, branches, .. }) in repositories.iter().enumerate() {
        let (owner, name) = repository.split_once('/').unwrap_or((repository, ""));
        declarations.push(format!("$o{index}: String!, $n{index}: String!"));
        variables.insert(format!("o{index}"), json!(owner));
        variables.insert(format!("n{index}"), json!(name));

        let mut fields = String::from("defaultBranchRef { name }");
        for (slot, branch) in branches.iter().enumerate() {
            declarations.push(format!("$h{index}_{slot}: String!"));
            variables.insert(format!("h{index}_{slot}"), json!(branch));
            fields.push_str(&format!(
                " b{slot}: pullRequests(headRefName: $h{index}_{slot}, first: {PER_BRANCH}, \
                 orderBy: {{field: CREATED_AT, direction: DESC}}) {{ nodes {{ number url title \
                 state isDraft mergedAt updatedAt headRepository {{ nameWithOwner }} }} }}"
            ));
        }
        selections.push(format!(
            "r{index}: repository(owner: $o{index}, name: $n{index}) {{ {fields} }}"
        ));
    }
    let query = format!("query({}) {{ {} }}", declarations.join(", "), selections.join(" "));
    (query, Value::Object(variables))
}

/// The newest pull request among `nodes`, which GitHub lists newest first,
/// that comes from a branch of `repository` itself and not from a fork.
fn newest(nodes: Vec<Node>, repository: &str) -> Option<PullRequest> {
    nodes.into_iter().find_map(|node| {
        let head = node.head_repository?;
        if !head.name_with_owner.eq_ignore_ascii_case(repository) {
            return None;
        }
        let state = match node.state.as_str() {
            "OPEN" => PullRequestState::Open,
            "MERGED" => PullRequestState::Merged,
            "CLOSED" => PullRequestState::Closed,
            _ => return None,
        };
        Some(PullRequest {
            number: node.number,
            url: node.url,
            title: node.title,
            state,
            is_draft: node.is_draft,
            merged_at: node.merged_at,
            updated_at: node.updated_at,
        })
    })
}

#[derive(Deserialize)]
struct Reply {
    data: Option<HashMap<String, Option<RepositoryData>>>,
    errors: Option<Vec<GraphQlError>>,
}

#[derive(Deserialize)]
struct GraphQlError {
    message: String,
    #[serde(rename = "type")]
    kind: Option<String>,
}

#[derive(Deserialize)]
struct RepositoryData {
    #[serde(rename = "defaultBranchRef")]
    default_branch_ref: Option<BranchName>,
    #[serde(flatten)]
    branches: HashMap<String, Connection>,
}

#[derive(Deserialize)]
struct BranchName {
    name: String,
}

#[derive(Deserialize)]
struct Connection {
    nodes: Vec<Node>,
}

#[derive(Deserialize)]
struct Node {
    number: u64,
    url: String,
    title: String,
    state: String,
    #[serde(rename = "isDraft")]
    is_draft: bool,
    #[serde(rename = "mergedAt")]
    merged_at: Option<String>,
    #[serde(rename = "updatedAt")]
    updated_at: String,
    #[serde(rename = "headRepository")]
    head_repository: Option<HeadRepository>,
}

#[derive(Deserialize)]
struct HeadRepository {
    #[serde(rename = "nameWithOwner")]
    name_with_owner: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_wait_doubles_to_ten_minutes_and_no_further() {
        let waits: Vec<u64> = (0..8).map(interval).collect();
        assert_eq!(waits, [60, 120, 240, 480, 600, 600, 600, 600]);
        assert_eq!(interval(u32::MAX), 600);
    }

    #[test]
    fn names_and_branches_are_variables() {
        let (query, variables) =
            build(&[Watched { key: "o/r", name: "o/r", branches: vec!["fix\"}) { evil"] }]);
        assert!(!query.contains("evil"));
        assert_eq!(variables["h0_0"], "fix\"}) { evil");
        assert_eq!(variables["o0"], "o");
        assert_eq!(variables["n0"], "r");
    }
}
