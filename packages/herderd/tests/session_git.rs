//! A git request over the wire, through `session::serve`.

mod common;

use common::Fixture;
use herderd::frame::{read_frame, write_frame};
use herderd::protocol::{
    ClientMessage, DaemonMessage, GitErrorCode, GitOp, GitResult, MAX_PROTOCOL, MIN_PROTOCOL,
    RepositoryKind,
};
use herderd::session::serve;
use std::io::Cursor;

fn exchange(messages: &[ClientMessage]) -> Vec<DaemonMessage> {
    let mut wire = Vec::new();
    for message in messages {
        write_frame(&mut wire, &serde_json::to_vec(message).unwrap()).unwrap();
    }
    let mut out = Vec::new();
    serve(Cursor::new(wire), &mut out).unwrap();

    let mut replies = Cursor::new(out);
    let mut all = Vec::new();
    while let Some(frame) = read_frame(&mut replies).unwrap() {
        all.push(serde_json::from_slice(&frame).unwrap());
    }
    all
}

fn hello() -> ClientMessage {
    ClientMessage::Hello {
        min_protocol: MIN_PROTOCOL,
        max_protocol: MAX_PROTOCOL,
        client: "test".into(),
    }
}

#[test]
fn answers_each_request_by_its_id() {
    let fixture = Fixture::new();
    let repo = fixture.repository("repo");
    let plain = fixture.directory("plain");
    let request = |id, path: &std::path::Path| ClientMessage::GitRequest {
        id,
        op: GitOp::RepositoryKind { path: path.to_str().unwrap().into() },
    };

    let replies = exchange(&[hello(), request(1, &repo), request(2, &plain)]);

    assert!(matches!(replies[0], DaemonMessage::Welcome { .. }));
    let mut answers: Vec<_> = replies[1..]
        .iter()
        .map(|reply| match reply {
            DaemonMessage::GitResponse {
                id,
                result: Some(GitResult::RepositoryKind(kind)),
                error: None,
            } => (*id, format!("{kind:?}")),
            other => panic!("unexpected reply: {other:?}"),
        })
        .collect();
    // Workers answer in any order.
    answers.sort();
    assert_eq!(
        answers,
        vec![
            (1, format!("{:?}", RepositoryKind::MainWorkingTree)),
            (2, format!("{:?}", RepositoryKind::NotARepository)),
        ]
    );
}

#[test]
fn error_codes_serialise_in_snake_case() {
    assert_eq!(
        serde_json::to_string(&GitErrorCode::InvalidRequest).unwrap(),
        r#""invalid_request""#
    );
}
