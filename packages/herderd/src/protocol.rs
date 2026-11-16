//! The messages of the first exchange, and the rules for choosing a version.
//!
//! Payloads are JSON, tagged by `type`. The first frame on every connection is
//! the client's [`ClientMessage::Hello`]; nothing else is accepted until the
//! daemon has answered it. Later versions add messages and fields and never
//! change the meaning of one, which is what lets a newer app talk to an older
//! daemon that is still holding sessions.

use serde::{Deserialize, Serialize};

/// The oldest protocol version this build speaks.
pub const MIN_PROTOCOL: u32 = 1;
/// The newest protocol version this build speaks.
pub const MAX_PROTOCOL: u32 = 1;

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
}

#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
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
    },
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
        assert_eq!(negotiate(1, 1), Some(1));
        assert_eq!(negotiate(1, 9), Some(MAX_PROTOCOL));
        assert_eq!(negotiate(0, 1), Some(1));
    }

    #[test]
    fn no_overlap_is_no_version() {
        assert_eq!(negotiate(MAX_PROTOCOL + 1, MAX_PROTOCOL + 3), None);
        assert_eq!(negotiate(0, MIN_PROTOCOL.saturating_sub(1)), None);
    }

    #[test]
    fn hello_is_tagged_json() {
        let hello = ClientMessage::Hello { min_protocol: 1, max_protocol: 2, client: "t".into() };
        let json = serde_json::to_string(&hello).unwrap();
        assert_eq!(json, r#"{"type":"hello","min_protocol":1,"max_protocol":2,"client":"t"}"#);
    }

    #[test]
    fn welcome_carries_the_host() {
        let welcome = DaemonMessage::Welcome {
            protocol: 1,
            daemon_version: "0.1.0".into(),
            host: HostId::local(),
        };
        let json = serde_json::to_string(&welcome).unwrap();
        assert_eq!(json, r#"{"type":"welcome","protocol":1,"daemon_version":"0.1.0","host":"local"}"#);
    }
}
