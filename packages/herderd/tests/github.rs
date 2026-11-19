//! The `viewer` check against a stub GraphQL server on a local port, and the
//! token messages over the wire through `session::serve_with`.

use herderd::frame::{read_frame, write_frame};
use herderd::github::GitHub;
use herderd::protocol::{
    ClientMessage, DaemonMessage, GitHubCheck, MAX_PROTOCOL, MIN_PROTOCOL, Secret,
};
use herderd::session::serve_with;
use std::io::{Cursor, Read, Write};
use std::net::TcpListener;
use std::sync::mpsc;
use std::thread;

const TOKEN: &str = "ghu_secret_token_value";

struct Stub {
    endpoint: String,
    requests: mpsc::Receiver<String>,
}

/// Answers each connection with `status` and `body`, and reports the request it
/// read, headers and all. Ends when the test drops the receiver.
fn stub(status: u16, body: &'static str) -> Stub {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let endpoint = format!("http://{}/graphql", listener.local_addr().unwrap());
    let (sender, requests) = mpsc::channel();
    thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { return };
            let mut request = Vec::new();
            let mut chunk = [0u8; 1024];
            while let Ok(count) = stream.read(&mut chunk) {
                if count == 0 {
                    break;
                }
                request.extend_from_slice(&chunk[..count]);
                let text = String::from_utf8_lossy(&request);
                if let Some((head, rest)) = text.split_once("\r\n\r\n") {
                    let length = head
                        .lines()
                        .find_map(|line| {
                            line.to_ascii_lowercase()
                                .strip_prefix("content-length:")
                                .map(|value| value.trim().parse::<usize>().unwrap())
                        })
                        .unwrap_or(0);
                    if rest.len() >= length {
                        break;
                    }
                }
            }
            let _ = sender.send(String::from_utf8_lossy(&request).into_owned());
            let reply = format!(
                "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
            let _ = stream.write_all(reply.as_bytes());
        }
    });
    Stub { endpoint, requests }
}

fn connected(endpoint: &str) -> GitHub {
    let github = GitHub::new(endpoint);
    github.set_token(Secret::new(TOKEN));
    github
}

#[test]
fn a_working_token_reports_its_login() {
    let server = stub(200, r#"{"data":{"viewer":{"login":"kurt"}}}"#);
    let github = connected(&server.endpoint);

    assert_eq!(github.check(), GitHubCheck::Ok { login: "kurt".into() });

    let request = server.requests.recv().unwrap();
    assert!(request.starts_with("POST /graphql"));
    assert!(
        request
            .to_ascii_lowercase()
            .contains(&format!("authorization: bearer {TOKEN}").to_ascii_lowercase())
    );
    assert!(request.contains("viewer"));
}

#[test]
fn a_401_is_unauthorized() {
    let server = stub(401, r#"{"message":"Bad credentials"}"#);
    assert_eq!(connected(&server.endpoint).check(), GitHubCheck::Unauthorized);
}

#[test]
fn a_server_error_is_an_error_naming_the_status() {
    let server = stub(502, "");
    match connected(&server.endpoint).check() {
        GitHubCheck::Error { message } => assert!(message.contains("502"), "{message}"),
        other => panic!("unexpected: {other:?}"),
    }
}

#[test]
fn a_graphql_error_is_an_error_with_its_message() {
    let server = stub(200, r#"{"errors":[{"message":"Something broke"}]}"#);
    assert_eq!(
        connected(&server.endpoint).check(),
        GitHubCheck::Error { message: "Something broke".into() }
    );
}

#[test]
fn nothing_listening_is_an_error() {
    // A port that was free a moment ago and has nobody on it.
    let endpoint = {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        format!("http://{}/graphql", listener.local_addr().unwrap())
    };
    assert!(matches!(connected(&endpoint).check(), GitHubCheck::Error { .. }));
}

#[test]
fn an_error_never_quotes_the_token() {
    let server = stub(
        200,
        &*Box::leak(
            format!(r#"{{"errors":[{{"message":"bad token {TOKEN}"}}]}}"#).into_boxed_str(),
        ),
    );
    match connected(&server.endpoint).check() {
        GitHubCheck::Error { message } => {
            assert!(!message.contains(TOKEN), "{message}");
            assert!(message.contains("<redacted>"));
        }
        other => panic!("unexpected: {other:?}"),
    }
}

#[test]
fn without_a_token_it_is_not_connected_and_asks_nobody() {
    let server = stub(200, "{}");
    let github = GitHub::new(&server.endpoint);

    assert_eq!(github.check(), GitHubCheck::NotConnected);
    assert!(server.requests.try_recv().is_err());
}

#[test]
fn clearing_forgets_the_token() {
    let server = stub(200, r#"{"data":{"viewer":{"login":"kurt"}}}"#);
    let github = connected(&server.endpoint);
    github.clear_token();

    assert_eq!(github.check(), GitHubCheck::NotConnected);
}

fn exchange(github: &GitHub, messages: &[ClientMessage]) -> (Vec<DaemonMessage>, Vec<u8>) {
    let mut wire = Vec::new();
    let hello = ClientMessage::Hello {
        min_protocol: MIN_PROTOCOL,
        max_protocol: MAX_PROTOCOL,
        client: "test".into(),
    };
    write_frame(&mut wire, &serde_json::to_vec(&hello).unwrap()).unwrap();
    for message in messages {
        write_frame(&mut wire, &serde_json::to_vec(message).unwrap()).unwrap();
    }
    let mut out = Vec::new();
    serve_with(Cursor::new(wire), &mut out, github).unwrap();

    let raw = out.clone();
    let mut replies = Cursor::new(out);
    let mut all = Vec::new();
    while let Some(frame) = read_frame(&mut replies).unwrap() {
        all.push(serde_json::from_slice(&frame).unwrap());
    }
    (all, raw)
}

#[test]
fn setting_a_token_answers_with_what_the_check_found_and_never_the_token() {
    let server = stub(200, r#"{"data":{"viewer":{"login":"kurt"}}}"#);
    let github = GitHub::new(&server.endpoint);

    let (replies, raw) =
        exchange(&github, &[ClientMessage::SetGitHubToken { id: 3, token: Secret::new(TOKEN) }]);

    assert_eq!(
        replies[1],
        DaemonMessage::GitHubResponse {
            id: 3,
            check: GitHubCheck::Ok { login: "kurt".into() }
        }
    );
    assert!(!String::from_utf8_lossy(&raw).contains(TOKEN));
}

#[test]
fn the_token_outlives_the_connection_that_set_it() {
    let server = stub(200, r#"{"data":{"viewer":{"login":"kurt"}}}"#);
    let github = GitHub::new(&server.endpoint);
    exchange(&github, &[ClientMessage::SetGitHubToken { id: 1, token: Secret::new(TOKEN) }]);

    let (replies, _) = exchange(&github, &[ClientMessage::CheckGitHub { id: 2 }]);

    assert_eq!(
        replies[1],
        DaemonMessage::GitHubResponse {
            id: 2,
            check: GitHubCheck::Ok { login: "kurt".into() }
        }
    );
}

#[test]
fn clearing_over_the_wire_leaves_nothing_to_check() {
    let server = stub(200, r#"{"data":{"viewer":{"login":"kurt"}}}"#);
    let github = connected(&server.endpoint);

    let (cleared, _) = exchange(&github, &[ClientMessage::ClearGitHubToken { id: 1 }]);
    let (checked, _) = exchange(&github, &[ClientMessage::CheckGitHub { id: 2 }]);

    let not_connected =
        |id| DaemonMessage::GitHubResponse { id, check: GitHubCheck::NotConnected };
    assert_eq!(cleared[1], not_connected(1));
    assert_eq!(checked[1], not_connected(2));
}

#[test]
fn a_set_followed_by_a_clear_on_one_connection_leaves_nothing_held() {
    let server = stub(200, r#"{"data":{"viewer":{"login":"kurt"}}}"#);
    let github = GitHub::new(&server.endpoint);

    // Workers answer in any order, so the order the token is stored and
    // forgotten in must not depend on them.
    for round in 0..20 {
        exchange(
            &github,
            &[
                ClientMessage::SetGitHubToken { id: 1, token: Secret::new(TOKEN) },
                ClientMessage::ClearGitHubToken { id: 2 },
            ],
        );
        let (replies, _) = exchange(&github, &[ClientMessage::CheckGitHub { id: 3 }]);
        assert_eq!(
            replies[1],
            DaemonMessage::GitHubResponse { id: 3, check: GitHubCheck::NotConnected },
            "round {round}"
        );
    }
}
