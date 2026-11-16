//! One connection, over any byte stream.

use crate::frame::{read_frame, write_frame};
use crate::protocol::{ClientMessage, DaemonMessage, HostId, MAX_PROTOCOL, MIN_PROTOCOL, negotiate};
use std::io::{self, Read, Write};

/// Serves one client until it hangs up. Takes a reader and a writer rather than
/// a socket so the same code runs over a Unix socket, a child's stdio or a
/// test's buffers.
pub fn serve<R: Read, W: Write>(mut input: R, mut output: W) -> io::Result<()> {
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
                },
            }
        }
        // Not a hello: the first message is always one, so this is not a
        // client of ours. Close without answering.
        Err(_) => return Err(io::Error::new(io::ErrorKind::InvalidData, "expected hello")),
    };

    let incompatible = matches!(reply, DaemonMessage::Incompatible { .. });
    let bytes = serde_json::to_vec(&reply).map_err(io::Error::other)?;
    write_frame(&mut output, &bytes)?;
    if incompatible {
        return Ok(());
    }

    // No further messages exist yet: hold the connection until the client
    // leaves, ignoring what it sends.
    while read_frame(&mut input)?.is_some() {}
    Ok(())
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
            min_protocol: 1,
            max_protocol: 1,
            client: "test".into(),
        });
        assert_eq!(
            reply,
            DaemonMessage::Welcome {
                protocol: 1,
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
            DaemonMessage::Incompatible { min_protocol: MIN_PROTOCOL, max_protocol: MAX_PROTOCOL, .. }
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
