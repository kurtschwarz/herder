//! The local transport: a Unix domain socket only its owner can use.
//!
//! This is the one module that knows the connection is a local socket. The
//! protocol and [`crate::session`] above it take any byte stream.

use crate::idle::Activity;
use crate::session;
use std::io;
use std::os::fd::AsRawFd;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::sync::Arc;
use std::thread;
use std::time::Duration;

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

/// Serves clients on `listener` until the daemon has been idle for `grace`,
/// then closes in an order that never leaves a client talking to a daemon that
/// is going away: stop accepting, remove the socket, return.
///
/// Returns once the socket is gone, so the caller can exit. Connections already
/// being served are not waited for: there are none, or the daemon was not idle.
pub fn serve_until_idle(listener: UnixListener, path: &Path, grace: Duration) -> io::Result<()> {
    let activity = Activity::new();
    let acceptor = {
        let activity = Arc::clone(&activity);
        thread::spawn(move || accept_until_closed(&listener, &activity))
    };

    activity.wait_until_idle_for(grace);

    // The accept thread is blocked in `accept`. Closed, it refuses the next
    // connection and ends, and a connection of our own is that next one.
    let _ = UnixStream::connect(path);
    let _ = acceptor.join();

    match std::fs::remove_file(path) {
        Err(error) if error.kind() != io::ErrorKind::NotFound => Err(error),
        _ => Ok(()),
    }
}

fn accept_until_closed(listener: &UnixListener, activity: &Arc<Activity>) {
    for stream in listener.incoming() {
        // A failed accept (no descriptors left, a client that gave up) must
        // not end a daemon that will own every session.
        let Ok(stream) = stream else { continue };
        if !matches!(peer_is_owner(&stream), Ok(true)) {
            continue;
        }
        let Some(hold) = activity.client() else { return };
        thread::spawn(move || {
            let _hold = hold;
            if let Ok(reader) = stream.try_clone() {
                let _ = session::serve(reader, stream);
            }
        });
    }
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
    use std::sync::mpsc;

    fn scratch(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("herderd-{name}-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        // `bind` narrows the umask for the whole process, so a directory made
        // while another test is binding comes out unusable.
        std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o700)).unwrap();
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

    const GRACE: Duration = Duration::from_millis(150);

    fn serve_in_background(path: &Path) -> mpsc::Receiver<io::Result<()>> {
        let listener = bind(path).unwrap();
        let path = path.to_path_buf();
        let (sender, receiver) = mpsc::channel();
        thread::spawn(move || {
            let _ = sender.send(serve_until_idle(listener, &path, GRACE));
        });
        receiver
    }

    #[test]
    fn exits_when_idle_and_removes_its_socket() {
        let path = scratch("idle");
        let done = serve_in_background(&path);
        done.recv_timeout(Duration::from_secs(5)).expect("exits when idle").unwrap();
        assert!(!path.exists());
        // The next app finds nothing, so it starts the bundled daemon.
        assert!(UnixStream::connect(&path).is_err());
    }

    #[test]
    fn a_connected_client_keeps_it_running_until_it_leaves() {
        let path = scratch("held");
        let done = serve_in_background(&path);
        let client = UnixStream::connect(&path).unwrap();

        assert!(done.recv_timeout(GRACE * 4).is_err());
        assert!(path.exists());

        drop(client);
        done.recv_timeout(Duration::from_secs(5)).expect("exits after the client leaves").unwrap();
        assert!(!path.exists());
    }

    #[test]
    fn a_client_arriving_during_the_countdown_cancels_it() {
        let path = scratch("cancel");
        let done = serve_in_background(&path);
        thread::sleep(GRACE / 2);
        let client = UnixStream::connect(&path).unwrap();
        assert!(done.recv_timeout(GRACE * 4).is_err());
        drop(client);
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
