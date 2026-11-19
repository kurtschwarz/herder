//! One connection, over any byte stream.

use crate::frame::{read_frame, write_frame};
use crate::git;
use crate::github::GitHub;
use crate::protocol::{
    ClientMessage, DaemonMessage, GitHubCheck, GitOp, HostId, MAX_PROTOCOL, MIN_PROTOCOL,
    negotiate,
};
use std::io::{self, Read, Write};
use std::sync::{Mutex, mpsc};
use std::thread;

/// How many git requests run at once for one connection. Bounded so a burst of
/// requests cannot start a thread, and a repository walk, apiece.
const GIT_WORKERS: usize = 4;

/// What `incompatible` reports as the sessions this daemon owns. None exist
/// yet. When they do, this must become the live count: an app ends a daemon
/// that reports 0.
const OWNED_SESSIONS: u32 = 0;

/// One request, waiting for a worker.
enum Job {
    Git(u64, GitOp),
    CheckGitHub(u64),
    /// The token is already forgotten; this is only the answer.
    ClearedGitHub(u64),
}

/// Serves one client until it hangs up. Takes a reader and a writer rather than
/// a socket so the same code runs over a Unix socket, a child's stdio or a
/// test's buffers.
pub fn serve<R: Read, W: Write + Send>(input: R, output: W) -> io::Result<()> {
    serve_with(input, output, GitHub::shared())
}

/// [`serve`] with the GitHub state to use, so a test has one of its own.
pub fn serve_with<R: Read, W: Write + Send>(
    mut input: R,
    mut output: W,
    github: &GitHub,
) -> io::Result<()> {
    let Some(first) = read_frame(&mut input)? else {
        return Ok(());
    };

    let reply = match serde_json::from_slice::<ClientMessage>(&first) {
        Ok(ClientMessage::Hello { min_protocol, max_protocol, .. }) => {
            match negotiate(min_protocol, max_protocol) {
                Some(protocol) => DaemonMessage::Welcome {
                    protocol,
                    daemon_version: env!("CARGO_PKG_VERSION").to_string(),
                    host: HostId::local(),
                },
                None => DaemonMessage::Incompatible {
                    min_protocol: MIN_PROTOCOL,
                    max_protocol: MAX_PROTOCOL,
                    daemon_version: env!("CARGO_PKG_VERSION").to_string(),
                    sessions: OWNED_SESSIONS,
                },
            }
        }
        // Not a hello: the first message is always one, so this is not a
        // client of ours. Close without answering.
        Ok(ClientMessage::GitRequest { .. }
        | ClientMessage::SetGitHubToken { .. }
        | ClientMessage::ClearGitHubToken { .. }
        | ClientMessage::CheckGitHub { .. })
        | Err(_) => {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "expected hello"));
        }
    };

    let incompatible = matches!(reply, DaemonMessage::Incompatible { .. });
    let bytes = serde_json::to_vec(&reply).map_err(io::Error::other)?;
    write_frame(&mut output, &bytes)?;
    if incompatible {
        return Ok(());
    }

    serve_requests(input, output, github)
}

/// Reads requests until the client leaves, answering git requests on a small
/// pool of workers. Responses may arrive in any order; `id` ties each to its
/// request.
fn serve_requests<R: Read, W: Write + Send>(
    mut input: R,
    output: W,
    github: &GitHub,
) -> io::Result<()> {
    let output = Mutex::new(output);
    let (jobs, queue) = mpsc::channel::<Job>();
    let queue = Mutex::new(queue);

    thread::scope(|scope| {
        for _ in 0..GIT_WORKERS {
            scope.spawn(|| {
                loop {
                    // The lock is released before the work starts.
                    let next = queue.lock().ok().and_then(|queue| queue.recv().ok());
                    let Some(job) = next else { return };
                    let reply = respond(job, github);
                    let Ok(bytes) = serde_json::to_vec(&reply) else {
                        continue;
                    };
                    if let Ok(mut output) = output.lock() {
                        let _ = write_frame(&mut *output, &bytes);
                    }
                }
            });
        }

        // Dropping `jobs` when this loop ends is what lets the workers finish.
        let result = (|| {
            while let Some(frame) = read_frame(&mut input)? {
                // Anything else is ignored: a newer client may say more than
                // this daemon knows.
                let job = match serde_json::from_slice(&frame) {
                    Ok(ClientMessage::GitRequest { id, op }) => Job::Git(id, op),
                    // Stored and forgotten here, in the order they arrive, and
                    // not on a worker: a set followed by a clear must end with
                    // nothing held, and workers run in any order.
                    Ok(ClientMessage::SetGitHubToken { id, token }) => {
                        github.set_token(token);
                        Job::CheckGitHub(id)
                    }
                    Ok(ClientMessage::ClearGitHubToken { id }) => {
                        github.clear_token();
                        Job::ClearedGitHub(id)
                    }
                    Ok(ClientMessage::CheckGitHub { id }) => Job::CheckGitHub(id),
                    Ok(ClientMessage::Hello { .. }) | Err(_) => continue,
                };
                let _ = jobs.send(job);
            }
            Ok(())
        })();
        drop(jobs);
        result
    })
}

fn respond(job: Job, github: &GitHub) -> DaemonMessage {
    match job {
        Job::Git(id, op) => match git::handle(&op) {
            Ok(result) => DaemonMessage::GitResponse { id, result: Some(result), error: None },
            Err(error) => DaemonMessage::GitResponse { id, result: None, error: Some(error) },
        },
        Job::ClearedGitHub(id) => {
            DaemonMessage::GitHubResponse { id, check: GitHubCheck::NotConnected }
        }
        Job::CheckGitHub(id) => DaemonMessage::GitHubResponse { id, check: github.check() },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    fn exchange(hello: &ClientMessage) -> DaemonMessage {
        let mut wire = Vec::new();
        write_frame(&mut wire, &serde_json::to_vec(hello).unwrap()).unwrap();
        let mut out = Vec::new();
        serve(Cursor::new(wire), &mut out).unwrap();
        let reply = read_frame(&mut Cursor::new(out)).unwrap().unwrap();
        serde_json::from_slice(&reply).unwrap()
    }

    #[test]
    fn welcomes_a_compatible_client() {
        let reply = exchange(&ClientMessage::Hello {
            min_protocol: MIN_PROTOCOL,
            max_protocol: MAX_PROTOCOL,
            client: "test".into(),
        });
        assert_eq!(
            reply,
            DaemonMessage::Welcome {
                protocol: MAX_PROTOCOL,
                daemon_version: env!("CARGO_PKG_VERSION").into(),
                host: HostId::local(),
            }
        );
    }

    #[test]
    fn reports_its_range_to_a_client_it_cannot_serve() {
        let reply = exchange(&ClientMessage::Hello {
            min_protocol: MAX_PROTOCOL + 1,
            max_protocol: MAX_PROTOCOL + 1,
            client: "test".into(),
        });
        assert!(matches!(
            reply,
            DaemonMessage::Incompatible {
                min_protocol: MIN_PROTOCOL,
                max_protocol: MAX_PROTOCOL,
                sessions: 0,
                ..
            }
        ));
    }

    #[test]
    fn a_first_frame_that_is_not_hello_is_refused() {
        let mut wire = Vec::new();
        write_frame(&mut wire, br#"{"type":"nope"}"#).unwrap();
        let mut out = Vec::new();
        assert!(serve(Cursor::new(wire), &mut out).is_err());
        assert!(out.is_empty());
    }

    #[test]
    fn a_client_that_leaves_without_speaking_is_not_an_error() {
        let mut out = Vec::new();
        serve(Cursor::new(Vec::new()), &mut out).unwrap();
        assert!(out.is_empty());
    }
}
