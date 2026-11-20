//! Pull request queries against a stub GraphQL server on a local port, and the
//! messages over the wire through `session::serve_with`.

mod common;

use common::Fixture;
use common::stub::stub;
use herderd::frame::{read_frame, write_frame};
use herderd::github::GitHub;
use herderd::protocol::{
    BranchPullRequest, ClientMessage, DaemonMessage, MAX_PROTOCOL, MIN_PROTOCOL, PullRequest,
    PullRequestRepo, PullRequestRepoStatus, PullRequestState, RepoPullRequests, Secret,
};
use herderd::session::serve_with;
use std::io::Cursor;
use std::path::Path;

const TOKEN: &str = "ghu_secret_token_value";

fn connected(endpoint: &str) -> GitHub {
    let github = GitHub::new(endpoint);
    github.set_token(Secret::new(TOKEN));
    github
}

fn ask(path: &Path, branches: &[&str]) -> Vec<PullRequestRepo> {
    vec![PullRequestRepo {
        path: path.to_str().unwrap().into(),
        branches: branches.iter().map(|branch| branch.to_string()).collect(),
    }]
}

fn node(number: u64, state: &str, head: &str) -> String {
    format!(
        r#"{{"number":{number},"url":"https://github.com/o/r/pull/{number}","title":"Pull {number}","state":"{state}","isDraft":false,"mergedAt":null,"updatedAt":"2026-01-02T03:04:05Z","headRepository":{{"nameWithOwner":"{head}"}}}}"#
    )
}

/// A reply for repository `o/r` whose branches are `b0`, `b1`, … in the order
/// given, each holding the nodes listed.
fn reply(default_branch: &str, branches: &[&[String]]) -> String {
    let fields: Vec<String> = branches
        .iter()
        .enumerate()
        .map(|(slot, nodes)| format!(r#""b{slot}":{{"nodes":[{}]}}"#, nodes.join(",")))
        .collect();
    format!(
        r#"{{"data":{{"r0":{{"defaultBranchRef":{{"name":"{default_branch}"}},{}}}}}}}"#,
        fields.join(",")
    )
}

fn pull(number: u64, state: PullRequestState) -> PullRequest {
    PullRequest {
        number,
        url: format!("https://github.com/o/r/pull/{number}"),
        title: format!("Pull {number}"),
        state,
        is_draft: false,
        merged_at: None,
        updated_at: "2026-01-02T03:04:05Z".into(),
    }
}

fn only(repos: Vec<RepoPullRequests>) -> RepoPullRequests {
    assert_eq!(repos.len(), 1, "{repos:?}");
    repos.into_iter().next().unwrap()
}

#[test]
fn a_branch_with_a_pull_request_is_matched_to_it() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let server = stub(vec![(200, reply("main", &[&[node(7, "OPEN", "o/r")]]))]);

    let (repos, next) = connected(&server.endpoint).pull_requests(&ask(&repo, &["feature"]));

    let found = only(repos);
    assert_eq!(found.repository, "o/r");
    assert_eq!(found.status, PullRequestRepoStatus::Ok);
    assert_eq!(found.default_branch.as_deref(), Some("main"));
    assert_eq!(
        found.branches,
        [BranchPullRequest {
            branch: "feature".into(),
            pull_request: Some(pull(7, PullRequestState::Open))
        }]
    );
    assert_eq!(next, 60);

    let request = server.requests.recv().unwrap();
    assert!(request.starts_with("POST /graphql"));
    assert!(
        request
            .to_ascii_lowercase()
            .contains(&format!("authorization: bearer {TOKEN}").to_ascii_lowercase())
    );
    assert!(request.contains("headRefName"));
}

#[test]
fn a_merged_and_a_draft_pull_request_say_so() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "https://github.com/o/r.git");
    let merged = node(4, "MERGED", "o/r")
        .replace(r#""mergedAt":null"#, r#""mergedAt":"2026-01-03T00:00:00Z""#);
    let draft = node(5, "OPEN", "o/r").replace(r#""isDraft":false"#, r#""isDraft":true"#);
    let server = stub(vec![(200, reply("main", &[&[merged], &[draft]]))]);

    let (repos, _) = connected(&server.endpoint).pull_requests(&ask(&repo, &["done", "wip"]));

    let found = only(repos);
    let done = found.branches[0].pull_request.as_ref().unwrap();
    assert_eq!(done.state, PullRequestState::Merged);
    assert_eq!(done.merged_at.as_deref(), Some("2026-01-03T00:00:00Z"));
    assert!(found.branches[1].pull_request.as_ref().unwrap().is_draft);
}

#[test]
fn a_branch_with_none_has_none() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let server = stub(vec![(200, reply("main", &[&[]]))]);

    let (repos, _) = connected(&server.endpoint).pull_requests(&ask(&repo, &["lonely"]));

    assert_eq!(
        only(repos).branches,
        [BranchPullRequest { branch: "lonely".into(), pull_request: None }]
    );
}

#[test]
fn a_pull_request_from_a_fork_is_not_ours() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    // The fork's is the newest, the repository's own is under it, and a third
    // has lost its fork altogether.
    let orphan = node(9, "OPEN", "o/r").replace(r#"{"nameWithOwner":"o/r"}"#, "null");
    let server = stub(vec![(
        200,
        reply("main", &[&[orphan, node(8, "OPEN", "stranger/r"), node(3, "CLOSED", "o/r")]]),
    )]);

    let (repos, _) = connected(&server.endpoint).pull_requests(&ask(&repo, &["feature"]));

    assert_eq!(only(repos).branches[0].pull_request, Some(pull(3, PullRequestState::Closed)));
}

#[test]
fn the_newest_of_several_wins() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    // GitHub lists them newest first.
    let server =
        stub(vec![(200, reply("main", &[&[node(12, "OPEN", "o/r"), node(2, "CLOSED", "o/r")]]))]);

    let (repos, _) = connected(&server.endpoint).pull_requests(&ask(&repo, &["feature"]));

    assert_eq!(only(repos).branches[0].pull_request.as_ref().unwrap().number, 12);
}

#[test]
fn the_default_branch_is_never_given_one_and_is_reported() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let server = stub(vec![(200, reply("main", &[&[node(1, "MERGED", "o/r")]]))]);

    let (repos, _) = connected(&server.endpoint).pull_requests(&ask(&repo, &["main"]));

    let found = only(repos);
    assert_eq!(found.default_branch.as_deref(), Some("main"));
    assert_eq!(found.branches[0].pull_request, None);
}

#[test]
fn every_repository_and_branch_is_one_request() {
    let fixture = Fixture::new();
    let first = fixture.repository_with_origin("first", "git@github.com:o/r.git");
    let second = fixture.repository_with_origin("second", "git@github.com:o/s.git");
    let body = r#"{"data":{"r0":{"defaultBranchRef":{"name":"main"},"b0":{"nodes":[]},"b1":{"nodes":[]}},"r1":{"defaultBranchRef":{"name":"main"},"b0":{"nodes":[]}}}}"#;
    let server = stub(vec![(200, body.into())]);
    let asked = vec![
        PullRequestRepo {
            path: first.to_str().unwrap().into(),
            branches: vec!["a".into(), "b".into()],
        },
        PullRequestRepo { path: second.to_str().unwrap().into(), branches: vec!["c".into()] },
    ];

    let (repos, _) = connected(&server.endpoint).pull_requests(&asked);

    assert_eq!(repos.len(), 2);
    assert_eq!(repos[0].branches.len(), 2);
    assert_eq!(repos[1].repository, "o/s");
    server.requests.recv().unwrap();
    assert!(server.requests.try_recv().is_err());
}

#[test]
fn a_repository_the_app_cannot_see_is_not_accessible() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let body = r#"{"data":{"r0":null},"errors":[{"type":"NOT_FOUND","path":["r0"],"message":"Could not resolve to a Repository with the name 'o/r'."}]}"#;
    let server = stub(vec![(200, body.into())]);

    let (repos, next) = connected(&server.endpoint).pull_requests(&ask(&repo, &["feature"]));

    let found = only(repos);
    assert_eq!(found.status, PullRequestRepoStatus::NotAccessible);
    assert!(found.branches.is_empty());
    assert_eq!(next, 60);
}

#[test]
fn a_remote_that_is_not_github_is_skipped_without_a_request() {
    let fixture = Fixture::new();
    let gitlab = fixture.repository_with_origin("gitlab", "git@gitlab.com:o/r.git");
    let none = fixture.repository("none");
    let plain = fixture.directory("plain");
    let server = stub(vec![(200, "{}".into())]);
    let github = connected(&server.endpoint);

    for path in [&gitlab, &none, &plain] {
        let (repos, next) = github.pull_requests(&ask(path, &["feature"]));
        assert!(repos.is_empty());
        assert_eq!(next, 60);
    }
    assert!(server.requests.try_recv().is_err());
}

#[test]
fn a_401_is_unauthorized_and_does_not_slow_the_poll() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let server = stub(vec![(401, r#"{"message":"Bad credentials"}"#.into())]);
    let github = connected(&server.endpoint);

    for _ in 0..3 {
        let (repos, next) = github.pull_requests(&ask(&repo, &["feature"]));
        assert_eq!(only(repos).status, PullRequestRepoStatus::Unauthorized);
        assert_eq!(next, 60);
    }
}

#[test]
fn without_a_token_it_is_unauthorized_and_asks_nobody() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let server = stub(vec![(200, "{}".into())]);

    let (repos, _) = GitHub::new(&server.endpoint).pull_requests(&ask(&repo, &["feature"]));

    assert_eq!(only(repos).status, PullRequestRepoStatus::Unauthorized);
    assert!(server.requests.try_recv().is_err());
}

#[test]
fn failures_keep_the_last_good_answer_and_double_the_wait_to_ten_minutes() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let good = reply("main", &[&[node(7, "OPEN", "o/r")]]);
    let rate_limited =
        r#"{"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded"}]}"#;
    let server = stub(vec![
        (200, good),
        (502, String::new()),
        (200, rate_limited.into()),
        (403, r#"{"message":"secondary rate limit"}"#.into()),
        (503, String::new()),
        (503, String::new()),
        (503, String::new()),
    ]);
    let github = connected(&server.endpoint);
    let asked = ask(&repo, &["feature"]);

    let (first, wait) = github.pull_requests(&asked);
    assert_eq!(only(first).status, PullRequestRepoStatus::Ok);
    assert_eq!(wait, 60);

    let mut waits = Vec::new();
    for _ in 0..6 {
        let (repos, wait) = github.pull_requests(&asked);
        let found = only(repos);
        assert!(matches!(found.status, PullRequestRepoStatus::Error { .. }), "{:?}", found.status);
        assert_eq!(
            found.branches[0].pull_request,
            Some(pull(7, PullRequestState::Open)),
            "the last good answer is kept"
        );
        waits.push(wait);
    }
    assert_eq!(waits, [120, 240, 480, 600, 600, 600]);
}

#[test]
fn a_success_after_failures_resets_the_wait() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let server =
        stub(vec![(500, String::new()), (500, String::new()), (200, reply("main", &[&[]]))]);
    let github = connected(&server.endpoint);
    let asked = ask(&repo, &["feature"]);

    assert_eq!(github.pull_requests(&asked).1, 120);
    assert_eq!(github.pull_requests(&asked).1, 240);
    let (repos, wait) = github.pull_requests(&asked);
    assert_eq!(only(repos).status, PullRequestRepoStatus::Ok);
    assert_eq!(wait, 60);
}

#[test]
fn nothing_listening_is_an_error_naming_no_token() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let endpoint = {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        format!("http://{}/graphql", listener.local_addr().unwrap())
    };

    let (repos, wait) = connected(&endpoint).pull_requests(&ask(&repo, &["feature"]));

    match only(repos).status {
        PullRequestRepoStatus::Error { message } => assert!(!message.contains(TOKEN), "{message}"),
        other => panic!("unexpected: {other:?}"),
    }
    assert_eq!(wait, 120);
}

#[test]
fn an_error_never_quotes_the_token() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let body = format!(r#"{{"errors":[{{"message":"bad token {TOKEN}"}}]}}"#);
    let server = stub(vec![(200, body)]);

    let (repos, _) = connected(&server.endpoint).pull_requests(&ask(&repo, &["feature"]));

    match only(repos).status {
        PullRequestRepoStatus::Error { message } => {
            assert!(!message.contains(TOKEN), "{message}");
            assert!(message.contains("<redacted>"));
        }
        other => panic!("unexpected: {other:?}"),
    }
}

#[test]
fn a_query_over_the_wire_is_answered_with_the_same_id() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let server = stub(vec![(200, reply("main", &[&[node(7, "OPEN", "o/r")]]))]);
    let github = connected(&server.endpoint);

    let mut wire = Vec::new();
    let hello = ClientMessage::Hello {
        min_protocol: MIN_PROTOCOL,
        max_protocol: MAX_PROTOCOL,
        client: "test".into(),
    };
    write_frame(&mut wire, &serde_json::to_vec(&hello).unwrap()).unwrap();
    let query = ClientMessage::PullRequestQuery { id: 5, repos: ask(&repo, &["feature"]) };
    write_frame(&mut wire, &serde_json::to_vec(&query).unwrap()).unwrap();
    let mut out = Vec::new();
    serve_with(Cursor::new(wire), &mut out, &github).unwrap();

    let mut replies = Cursor::new(out);
    read_frame(&mut replies).unwrap().unwrap();
    let frame = read_frame(&mut replies).unwrap().unwrap();
    match serde_json::from_slice::<DaemonMessage>(&frame).unwrap() {
        DaemonMessage::PullRequestResponse { id, repos, next_poll_seconds } => {
            assert_eq!(id, 5);
            assert_eq!(only(repos).branches[0].pull_request.as_ref().unwrap().number, 7);
            assert_eq!(next_poll_seconds, 60);
        }
        other => panic!("unexpected: {other:?}"),
    }
}

#[test]
fn two_folders_of_one_repository_are_one_repository() {
    let fixture = Fixture::new();
    // The same repository, spelled differently, cloned twice.
    let first = fixture.repository_with_origin("first", "git@github.com:o/r.git");
    let second = fixture.repository_with_origin("second", "https://github.com/O/R");
    let body = reply("main", &[&[node(7, "OPEN", "o/r")], &[]]);
    let server = stub(vec![(200, body)]);
    let asked = vec![
        PullRequestRepo { path: first.to_str().unwrap().into(), branches: vec!["a".into()] },
        PullRequestRepo { path: second.to_str().unwrap().into(), branches: vec!["b".into()] },
    ];

    let (repos, _) = connected(&server.endpoint).pull_requests(&asked);

    assert_eq!(repos.len(), 2);
    for found in &repos {
        assert_eq!(found.status, PullRequestRepoStatus::Ok, "{found:?}");
    }
    assert_eq!(repos[0].branches[0].pull_request.as_ref().unwrap().number, 7);
    assert_eq!(repos[1].branches[0].pull_request, None);
    server.requests.recv().unwrap();
    assert!(server.requests.try_recv().is_err());
}
