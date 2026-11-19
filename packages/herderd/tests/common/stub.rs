//! A GraphQL server on a local port that answers from a script.

use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::mpsc;
use std::thread;

pub struct Stub {
    pub endpoint: String,
    /// Every request read, headers and all, in order.
    pub requests: mpsc::Receiver<String>,
}

/// Answers the first connection with the first of `replies`, the second with
/// the second, and every one after the last with the last. Ends when the test
/// drops the receiver.
pub fn stub(replies: Vec<(u16, String)>) -> Stub {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let endpoint = format!("http://{}/graphql", listener.local_addr().unwrap());
    let (sender, requests) = mpsc::channel();
    thread::spawn(move || {
        for (served, stream) in listener.incoming().enumerate() {
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
            let (status, body) = &replies[served.min(replies.len() - 1)];
            let reply = format!(
                "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
            let _ = stream.write_all(reply.as_bytes());
        }
    });
    Stub { endpoint, requests }
}
