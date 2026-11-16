//! The local transport: a Unix domain socket only its owner can use.
//!
//! This is the one module that knows the connection is a local socket. The
//! protocol and [`crate::session`] above it take any byte stream.

use std::io;
use std::os::fd::AsRawFd;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;

/// Binds the socket, replacing one left behind by a daemon that is gone.
///
/// Refuses if something is still answering on it: two daemons would each hold
/// half the sessions.
pub fn bind(path: &Path) -> io::Result<UnixListener> {
    if path.exists() {
        match UnixStream::connect(path) {
            Ok(_) => return Err(io::Error::new(io::ErrorKind::AddrInUse, "herderd is already running")),
            // Only these mean nobody is listening. Any other failure (no
            // descriptors left, no permission) says nothing about whether a
            // daemon is, and removing its socket would strand it.
            Err(error) if matches!(error.kind(), io::ErrorKind::ConnectionRefused | io::ErrorKind::NotFound) => {
                std::fs::remove_file(path)?;
            }
            Err(error) => return Err(error),
        }
    }
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    // The socket is created with the process umask applied, so tighten it
    // first: set afterwards, there is a moment it is open to others.
    // SAFETY: `umask` has no preconditions.
    let previous = unsafe { libc::umask(0o177) };
    let bound = UnixListener::bind(path);
    // SAFETY: as above.
    unsafe { libc::umask(previous) };
    let listener = bound?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
    Ok(listener)
}

/// The user id of whoever is on the other end of the socket.
pub fn peer_uid(stream: &UnixStream) -> io::Result<u32> {
    let mut uid: libc::uid_t = 0;
    let mut gid: libc::gid_t = 0;
    // SAFETY: the descriptor is open for the call and both out-pointers are
    // valid for it.
    let result = unsafe { libc::getpeereid(stream.as_raw_fd(), &mut uid, &mut gid) };
    if result == 0 { Ok(uid) } else { Err(io::Error::last_os_error()) }
}

/// Whether the peer is the same user the daemon runs as.
pub fn peer_is_owner(stream: &UnixStream) -> io::Result<bool> {
    // SAFETY: `geteuid` has no preconditions.
    Ok(peer_uid(stream)? == unsafe { libc::geteuid() })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("herderd-{name}-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        dir.join("d.sock")
    }

    #[test]
    fn the_socket_is_private_to_its_owner() {
        let path = scratch("mode");
        let _listener = bind(&path).unwrap();
        let mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600);
    }

    #[test]
    fn replaces_a_stale_socket_but_not_a_live_one() {
        let path = scratch("stale");
        drop(bind(&path).unwrap());
        // The file is still there with nobody listening.
        assert!(path.exists());
        let live = bind(&path).unwrap();
        assert_eq!(bind(&path).unwrap_err().kind(), io::ErrorKind::AddrInUse);
        drop(live);
    }

    #[test]
    fn the_peer_is_this_user() {
        let path = scratch("peer");
        let listener = bind(&path).unwrap();
        let _client = UnixStream::connect(&path).unwrap();
        let (server_side, _) = listener.accept().unwrap();
        assert!(peer_is_owner(&server_side).unwrap());
    }
}
