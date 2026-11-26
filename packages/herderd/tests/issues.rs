//! Issue queries against a stub GraphQL server on a local port, and the
//! messages over the wire through `session::serve_with`.

mod common;

use common::Fixture;
use common::stub::stub;
use herderd::frame::{read_frame, write_frame};
use herderd::github::GitHub;
use herderd::protocol::{
    ClientMessage, DaemonMessage, IssueFreshness, IssueRepoStatus, IssueTab, MAX_PROTOCOL,
    MIN_PROTOCOL, Secret,
};
use herderd::session::serve_with;
use std::io::Cursor;

const TOKEN: &str = "ghu_secret_token_value";
const VIEWER: &str = r#"{"data":{"viewer":{"login":"kurt"}}}"#;

fn connected(endpoint: &str) -> GitHub {
    let github = GitHub::new(endpoint);
    github.set_token(Secret::new(TOKEN));
    github
}

fn node(number: u64, title: &str) -> String {
    format!(
        r#"{{"number":{number},"url":"https://github.com/o/r/issues/{number}","title":"{title}","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-02T00:00:00Z","author":{{"login":"ada"}},"labels":{{"nodes":[{{"name":"bug","color":"d73a4a"}}]}},"comments":{{"totalCount":3}}}}"#
    )
}

/// A list reply showing `nodes` under `shown`, with the counts of both tabs.
fn list(shown: &str, nodes: &[String], assigned: u64, open: u64) -> String {
    let page = |name: &str, total: u64| {
        if name == shown {
            format!(
                r#""{name}":{{"totalCount":{total},"nodes":[{}]}}"#,
                nodes.join(",")
            )
        } else {
            format!(r#""{name}":{{"totalCount":{total}}}"#)
        }
    };
    format!(
        r#"{{"data":{{"repository":{{{},{}}}}}}}"#,
        page("assigned", assigned),
        page("open", open)
    )
}

fn detail(body: &str, comments: &str) -> String {
    format!(
        r#"{{"data":{{"repository":{{"issue":{{"number":9,"url":"https://github.com/o/r/issues/9","title":"Nine","body":{body},"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-02T00:00:00Z","author":{{"login":"ada"}},"labels":{{"nodes":[]}},"comments":{{"totalCount":2,"nodes":[{comments}]}}}}}}}}}}"#
    )
}

#[test]
fn a_fresh_query_lists_the_tab_and_counts_both() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let server = stub(vec![
        (200, VIEWER.into()),
        (200, list("open", &[node(7, "Seven"), node(6, "Six")], 1, 2)),
    ]);

    let found = connected(&server.endpoint).issues(
        repo.to_str().unwrap(),
        IssueTab::Open,
        IssueFreshness::Fresh,
    );

    assert_eq!(found.repository.as_deref(), Some("o/r"));
    assert_eq!(found.status, IssueRepoStatus::Ok);
    assert_eq!(
        found
            .issues
            .iter()
            .map(|issue| issue.number)
            .collect::<Vec<_>>(),
        [7, 6]
    );
    assert_eq!(found.issues[0].title, "Seven");
    assert_eq!(found.issues[0].author.as_deref(), Some("ada"));
    assert_eq!(found.issues[0].labels[0].name, "bug");
    assert_eq!(found.issues[0].comments, 3);
    assert_eq!((found.assigned_count, found.open_count), (Some(1), Some(2)));
    assert!(found.fetched_at.is_some());

    server.requests.recv().unwrap();
    let request = server.requests.recv().unwrap();
    assert!(request.contains("states: OPEN"));
    assert!(request.contains(r#""login": "kurt""#));
    assert!(
        request
            .to_ascii_lowercase()
            .contains(&format!("authorization: bearer {TOKEN}").to_ascii_lowercase())
    );
}

#[test]
fn the_assigned_tab_asks_for_the_signed_in_user() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let server = stub(vec![
        (200, VIEWER.into()),
        (200, list("assigned", &[node(4, "Four")], 1, 5)),
    ]);

    let found = connected(&server.endpoint).issues(
        repo.to_str().unwrap(),
        IssueTab::Assigned,
        IssueFreshness::Fresh,
    );

    assert_eq!(found.issues.len(), 1);
    server.requests.recv().unwrap();
    assert!(server.requests.recv().unwrap().contains("filterBy"));
}

#[test]
fn a_cached_query_with_nothing_held_asks_nobody() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let server = stub(vec![(200, "{}".into())]);

    let found = connected(&server.endpoint).issues(
        repo.to_str().unwrap(),
        IssueTab::Open,
        IssueFreshness::Cached,
    );

    assert_eq!(found.status, IssueRepoStatus::Ok);
    assert!(found.issues.is_empty());
    assert_eq!(found.fetched_at, None);
    assert!(server.requests.try_recv().is_err());
}

#[test]
fn a_fresh_answer_is_what_a_cached_query_gets_after() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let server = stub(vec![
        (200, VIEWER.into()),
        (200, list("open", &[node(7, "Seven")], 0, 1)),
    ]);
    let github = connected(&server.endpoint);
    let path = repo.to_str().unwrap();

    let fresh = github.issues(path, IssueTab::Open, IssueFreshness::Fresh);
    let cached = github.issues(path, IssueTab::Open, IssueFreshness::Cached);
    // Another tab was never asked.
    let other = github.issues(path, IssueTab::Assigned, IssueFreshness::Cached);

    assert_eq!(cached, fresh);
    assert_eq!(other.fetched_at, None);
    server.requests.recv().unwrap();
    server.requests.recv().unwrap();
    assert!(server.requests.try_recv().is_err());
}

#[test]
fn clearing_or_changing_the_token_drops_what_was_held() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let server = stub(vec![
        (200, VIEWER.into()),
        (200, list("open", &[node(7, "Seven")], 0, 1)),
    ]);
    let github = connected(&server.endpoint);
    let path = repo.to_str().unwrap();
    github.issues(path, IssueTab::Open, IssueFreshness::Fresh);

    // The same token again is the same account.
    github.set_token(Secret::new(TOKEN));
    assert_eq!(
        github
            .issues(path, IssueTab::Open, IssueFreshness::Cached)
            .issues
            .len(),
        1
    );

    github.set_token(Secret::new("ghu_someone_else"));
    assert_eq!(
        github
            .issues(path, IssueTab::Open, IssueFreshness::Cached)
            .fetched_at,
        None
    );

    github.set_token(Secret::new(TOKEN));
    github.issues(path, IssueTab::Open, IssueFreshness::Fresh);
    github.clear_token();
    github.set_token(Secret::new(TOKEN));
    assert_eq!(
        github
            .issues(path, IssueTab::Open, IssueFreshness::Cached)
            .fetched_at,
        None
    );
}

#[test]
fn a_cached_answer_belongs_to_the_user_who_was_signed_in() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let server = stub(vec![
        (200, VIEWER.into()),
        (200, list("open", &[node(7, "Seven")], 0, 1)),
        (200, r#"{"data":{"viewer":{"login":"grace"}}}"#.into()),
        (200, list("open", &[], 0, 0)),
    ]);
    let github = connected(&server.endpoint);
    let path = repo.to_str().unwrap();
    github.issues(path, IssueTab::Open, IssueFreshness::Fresh);

    github.set_token(Secret::new("ghu_grace"));
    let theirs = github.issues(path, IssueTab::Open, IssueFreshness::Fresh);

    assert!(theirs.issues.is_empty());
    assert_eq!(
        github
            .issues(path, IssueTab::Open, IssueFreshness::Cached)
            .open_count,
        Some(0)
    );
}

#[test]
fn a_repository_the_app_cannot_see_is_not_accessible() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let body = r#"{"data":{"repository":null},"errors":[{"type":"NOT_FOUND","path":["repository"],"message":"Could not resolve to a Repository with the name 'o/r'."}]}"#;
    let server = stub(vec![(200, VIEWER.into()), (200, body.into())]);

    let found = connected(&server.endpoint).issues(
        repo.to_str().unwrap(),
        IssueTab::Open,
        IssueFreshness::Fresh,
    );

    assert_eq!(found.status, IssueRepoStatus::NotAccessible);
    assert!(found.issues.is_empty());
}

#[test]
fn an_installation_without_the_issues_permission_says_so() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let body = r#"{"data":{"repository":{"assigned":null,"open":null}},"errors":[{"type":"FORBIDDEN","path":["repository","assigned"],"message":"Resource not accessible by integration"}]}"#;
    let server = stub(vec![(200, VIEWER.into()), (200, body.into())]);

    let found = connected(&server.endpoint).issues(
        repo.to_str().unwrap(),
        IssueTab::Open,
        IssueFreshness::Fresh,
    );

    assert_eq!(found.status, IssueRepoStatus::PermissionMissing);
}

#[test]
fn a_refused_token_is_unauthorized_and_so_is_none() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let path = repo.to_str().unwrap();
    let server = stub(vec![(401, r#"{"message":"Bad credentials"}"#.into())]);
    let refused = connected(&server.endpoint).issues(path, IssueTab::Open, IssueFreshness::Fresh);
    assert_eq!(refused.status, IssueRepoStatus::Unauthorized);

    let none = GitHub::new(&server.endpoint).issues(path, IssueTab::Open, IssueFreshness::Cached);
    assert_eq!(none.status, IssueRepoStatus::Unauthorized);
}

#[test]
fn a_401_after_the_viewer_is_unauthorized_too() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let server = stub(vec![(200, VIEWER.into()), (401, "{}".into())]);

    let found = connected(&server.endpoint).issues(
        repo.to_str().unwrap(),
        IssueTab::Open,
        IssueFreshness::Fresh,
    );

    assert_eq!(found.status, IssueRepoStatus::Unauthorized);
}

#[test]
fn github_failing_is_an_error_that_never_quotes_the_token() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let path = repo.to_str().unwrap();
    let body = format!(r#"{{"errors":[{{"message":"bad token {TOKEN}"}}]}}"#);
    let server = stub(vec![
        (200, VIEWER.into()),
        (200, body),
        (502, String::new()),
    ]);
    let github = connected(&server.endpoint);

    match github
        .issues(path, IssueTab::Open, IssueFreshness::Fresh)
        .status
    {
        IssueRepoStatus::Error { message } => {
            assert!(!message.contains(TOKEN), "{message}");
            assert!(message.contains("<redacted>"));
        }
        other => panic!("unexpected: {other:?}"),
    }
    match github
        .issues(path, IssueTab::Open, IssueFreshness::Fresh)
        .status
    {
        IssueRepoStatus::Error { message } => assert!(message.contains("502"), "{message}"),
        other => panic!("unexpected: {other:?}"),
    }
}

#[test]
fn a_failed_refresh_leaves_what_was_held() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let server = stub(vec![
        (200, VIEWER.into()),
        (200, list("open", &[node(7, "Seven")], 0, 1)),
        (503, String::new()),
    ]);
    let github = connected(&server.endpoint);
    let path = repo.to_str().unwrap();
    github.issues(path, IssueTab::Open, IssueFreshness::Fresh);

    let failed = github.issues(path, IssueTab::Open, IssueFreshness::Fresh);

    assert!(matches!(failed.status, IssueRepoStatus::Error { .. }));
    assert_eq!(
        github
            .issues(path, IssueTab::Open, IssueFreshness::Cached)
            .issues
            .len(),
        1
    );
}

#[test]
fn a_remote_that_is_not_github_is_an_error_without_a_request() {
    let fixture = Fixture::new();
    let gitlab = fixture.repository_with_origin("gitlab", "git@gitlab.com:o/r.git");
    let server = stub(vec![(200, "{}".into())]);

    let found = connected(&server.endpoint).issues(
        gitlab.to_str().unwrap(),
        IssueTab::Open,
        IssueFreshness::Fresh,
    );

    assert_eq!(found.repository, None);
    assert!(matches!(found.status, IssueRepoStatus::Error { .. }));
    assert!(server.requests.try_recv().is_err());
}

#[test]
fn an_issue_comes_with_its_body_and_comments() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let comments = r#"{"author":{"login":"bob"},"body":"first","createdAt":"2026-01-03T00:00:00Z"},{"author":null,"body":"second","createdAt":"2026-01-04T00:00:00Z"}"#;
    let server = stub(vec![(200, detail(r#""Do the thing.""#, comments))]);

    let reply = connected(&server.endpoint).issue_detail(repo.to_str().unwrap(), 9);

    assert_eq!(reply.status, IssueRepoStatus::Ok);
    let found = reply.detail.unwrap();
    assert_eq!(found.issue.number, 9);
    assert_eq!(found.issue.title, "Nine");
    assert_eq!(found.body, "Do the thing.");
    assert_eq!(found.comments.len(), 2);
    assert_eq!(found.comments[0].author.as_deref(), Some("bob"));
    assert_eq!(found.comments[1].author, None);
    assert_eq!(found.comments[1].body, "second");

    let request = server.requests.recv().unwrap();
    assert!(request.contains("comments(last: 50)"));
    assert!(request.contains(r#""number": 9"#));
}

#[test]
fn an_issue_with_no_body_has_an_empty_one() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let server = stub(vec![(200, detail("null", ""))]);

    let reply = connected(&server.endpoint).issue_detail(repo.to_str().unwrap(), 9);

    assert_eq!(reply.detail.unwrap().body, "");
}

#[test]
fn details_are_never_remembered() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let server = stub(vec![
        (200, detail(r#""old""#, "")),
        (200, detail(r#""new""#, "")),
    ]);
    let github = connected(&server.endpoint);
    let path = repo.to_str().unwrap();

    assert_eq!(github.issue_detail(path, 9).detail.unwrap().body, "old");
    assert_eq!(github.issue_detail(path, 9).detail.unwrap().body, "new");
}

#[test]
fn a_number_that_is_no_issue_has_no_detail() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let body = r#"{"data":{"repository":{"issue":null}},"errors":[{"type":"NOT_FOUND","path":["repository","issue"],"message":"Could not resolve to an Issue with the number of 9."}]}"#;
    let server = stub(vec![(200, body.into())]);

    let reply = connected(&server.endpoint).issue_detail(repo.to_str().unwrap(), 9);

    assert_eq!(reply.status, IssueRepoStatus::Ok);
    assert_eq!(reply.detail, None);
}

#[test]
fn a_detail_failure_has_a_status_and_no_detail() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let path = repo.to_str().unwrap();
    let forbidden = r#"{"data":{"repository":{"issue":null}},"errors":[{"type":"FORBIDDEN","path":["repository","issue"],"message":"Resource not accessible by integration"}]}"#;
    let server = stub(vec![
        (200, forbidden.into()),
        (401, "{}".into()),
        (500, String::new()),
    ]);
    let github = connected(&server.endpoint);

    assert_eq!(
        github.issue_detail(path, 9).status,
        IssueRepoStatus::PermissionMissing
    );
    assert_eq!(
        github.issue_detail(path, 9).status,
        IssueRepoStatus::Unauthorized
    );
    let failed = github.issue_detail(path, 9);
    assert!(matches!(failed.status, IssueRepoStatus::Error { .. }));
    assert_eq!(failed.detail, None);

    let none = GitHub::new(&server.endpoint).issue_detail(path, 9);
    assert_eq!(none.status, IssueRepoStatus::Unauthorized);
}

#[test]
fn the_messages_are_answered_over_the_wire_with_their_ids() {
    let fixture = Fixture::new();
    let repo = fixture.repository_with_origin("repo", "git@github.com:o/r.git");
    let path = repo.to_str().unwrap().to_string();
    let server = stub(vec![
        (200, VIEWER.into()),
        (200, list("open", &[node(7, "Seven")], 0, 1)),
        (200, detail(r#""Body""#, "")),
    ]);
    let github = connected(&server.endpoint);

    let mut wire = Vec::new();
    let hello = ClientMessage::Hello {
        min_protocol: MIN_PROTOCOL,
        max_protocol: MAX_PROTOCOL,
        client: "test".into(),
    };
    write_frame(&mut wire, &serde_json::to_vec(&hello).unwrap()).unwrap();
    let query = ClientMessage::IssueQuery {
        id: 5,
        path: path.clone(),
        tab: IssueTab::Open,
        freshness: IssueFreshness::Fresh,
    };
    write_frame(&mut wire, &serde_json::to_vec(&query).unwrap()).unwrap();
    let mut out = Vec::new();
    serve_with(Cursor::new(wire), &mut out, &github).unwrap();

    let mut replies = Cursor::new(out);
    read_frame(&mut replies).unwrap().unwrap();
    let frame = read_frame(&mut replies).unwrap().unwrap();
    match serde_json::from_slice::<DaemonMessage>(&frame).unwrap() {
        DaemonMessage::IssueResponse { id, result } => {
            assert_eq!(id, 5);
            assert_eq!(result.issues[0].number, 7);
        }
        other => panic!("unexpected: {other:?}"),
    }

    let mut wire = Vec::new();
    write_frame(&mut wire, &serde_json::to_vec(&hello).unwrap()).unwrap();
    let ask = ClientMessage::IssueDetail {
        id: 6,
        path,
        number: 9,
    };
    write_frame(&mut wire, &serde_json::to_vec(&ask).unwrap()).unwrap();
    let mut out = Vec::new();
    serve_with(Cursor::new(wire), &mut out, &github).unwrap();
    let mut replies = Cursor::new(out);
    read_frame(&mut replies).unwrap().unwrap();
    let frame = read_frame(&mut replies).unwrap().unwrap();
    match serde_json::from_slice::<DaemonMessage>(&frame).unwrap() {
        DaemonMessage::IssueDetailResponse { id, result } => {
            assert_eq!(id, 6);
            assert_eq!(result.detail.unwrap().body, "Body");
        }
        other => panic!("unexpected: {other:?}"),
    }
}
