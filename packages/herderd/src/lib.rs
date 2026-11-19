//! herderd: the daemon that owns Herder's agent sessions and terminal
//! processes, so they keep running when the app does not.
//!
//! The core is portable: [`frame`], [`protocol`], [`session`] and [`idle`] work
//! over any byte stream. Only [`transport`] knows the connection is a local
//! socket.

pub mod frame;
pub mod git;
pub mod idle;
pub mod protocol;
pub mod session;
pub mod transport;
