//! When the daemon has nothing to do.
//!
//! The daemon is idle when it owns no sessions and no client is connected. Once
//! it has been idle for the grace period it closes, and the caller exits. An
//! old daemon then does not outlive an app update: the next launch finds
//! nothing on the socket and starts the bundled binary. See ADR 0001.

use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::time::{Duration, Instant};

/// How long the daemon stays up with nothing to do.
pub const DEFAULT_GRACE: Duration = Duration::from_secs(10 * 60);

/// What keeps the daemon alive, shared between the connections that hold it.
pub struct Activity {
    state: Mutex<State>,
    changed: Condvar,
}

struct State {
    clients: usize,
    sessions: usize,
    idle_since: Instant,
    closed: bool,
}

impl State {
    fn is_idle(&self) -> bool {
        self.clients == 0 && self.sessions == 0
    }
}

#[derive(Clone, Copy)]
enum Kind {
    Client,
    Session,
}

/// Keeps the daemon from going idle until it is dropped.
pub struct Hold {
    activity: Arc<Activity>,
    kind: Kind,
}

impl Activity {
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            state: Mutex::new(State { clients: 0, sessions: 0, idle_since: Instant::now(), closed: false }),
            changed: Condvar::new(),
        })
    }

    /// A connected client. `None` once the daemon has closed, so a connection
    /// that arrives during shutdown is refused rather than half served.
    pub fn client(self: &Arc<Self>) -> Option<Hold> {
        self.acquire(Kind::Client)
    }

    /// An owned session. `None` once the daemon has closed.
    pub fn session(self: &Arc<Self>) -> Option<Hold> {
        self.acquire(Kind::Session)
    }

    fn acquire(self: &Arc<Self>, kind: Kind) -> Option<Hold> {
        let mut state = self.lock();
        if state.closed {
            return None;
        }
        match kind {
            Kind::Client => state.clients += 1,
            Kind::Session => state.sessions += 1,
        }
        self.changed.notify_all();
        Some(Hold { activity: Arc::clone(self), kind })
    }

    /// Blocks until the daemon has been idle for `grace`, then closes it. After
    /// this returns, [`Activity::client`] and [`Activity::session`] return `None`.
    pub fn wait_until_idle_for(&self, grace: Duration) {
        let mut state = self.lock();
        loop {
            if !state.is_idle() {
                state = self.changed.wait(state).unwrap_or_else(|poisoned| poisoned.into_inner());
                continue;
            }
            let elapsed = state.idle_since.elapsed();
            if elapsed >= grace {
                // Closed under the same lock that saw it idle, so nothing can
                // take a hold between the decision and the closing.
                state.closed = true;
                return;
            }
            state = self
                .changed
                .wait_timeout(state, grace - elapsed)
                .unwrap_or_else(|poisoned| poisoned.into_inner())
                .0;
        }
    }

    fn lock(&self) -> MutexGuard<'_, State> {
        // A panicking connection must not stop the daemon from ever closing.
        self.state.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

impl Drop for Hold {
    fn drop(&mut self) {
        let mut state = self.activity.lock();
        match self.kind {
            Kind::Client => state.clients -= 1,
            Kind::Session => state.sessions -= 1,
        }
        if state.is_idle() {
            state.idle_since = Instant::now();
        }
        self.activity.changed.notify_all();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;
    use std::thread;

    const GRACE: Duration = Duration::from_millis(100);

    /// Waits on another thread; the receiver gets a message when it returns.
    fn watch(activity: &Arc<Activity>, grace: Duration) -> mpsc::Receiver<Instant> {
        let (sender, receiver) = mpsc::channel();
        let activity = Arc::clone(activity);
        thread::spawn(move || {
            activity.wait_until_idle_for(grace);
            let _ = sender.send(Instant::now());
        });
        receiver
    }

    #[test]
    fn closes_after_the_grace_period_with_nothing_held() {
        let activity = Activity::new();
        let started = Instant::now();
        activity.wait_until_idle_for(GRACE);
        assert!(started.elapsed() >= GRACE);
        assert!(activity.client().is_none());
        assert!(activity.session().is_none());
    }

    #[test]
    fn a_client_keeps_it_open() {
        let activity = Activity::new();
        let _client = activity.client().unwrap();
        let closed = watch(&activity, GRACE);
        assert!(closed.recv_timeout(GRACE * 4).is_err());
    }

    #[test]
    fn a_session_keeps_it_open() {
        let activity = Activity::new();
        let _session = activity.session().unwrap();
        let closed = watch(&activity, GRACE);
        assert!(closed.recv_timeout(GRACE * 4).is_err());
    }

    #[test]
    fn the_last_hold_leaving_restarts_the_countdown() {
        let activity = Activity::new();
        let client = activity.client().unwrap();
        let session = activity.session().unwrap();
        let closed = watch(&activity, GRACE);

        drop(client);
        assert!(closed.recv_timeout(GRACE * 3).is_err(), "a session is still held");

        let released = Instant::now();
        drop(session);
        let at = closed.recv_timeout(GRACE * 10).expect("closes once nothing is held");
        assert!(at.duration_since(released) >= GRACE);
    }

    #[test]
    fn a_hold_taken_during_the_countdown_cancels_it() {
        let activity = Activity::new();
        let closed = watch(&activity, GRACE * 3);
        thread::sleep(GRACE);

        let client = activity.client().unwrap();
        assert!(closed.recv_timeout(GRACE * 6).is_err());

        let released = Instant::now();
        drop(client);
        let at = closed.recv_timeout(GRACE * 20).unwrap();
        // The countdown began again at release, not where it first started.
        assert!(at.duration_since(released) >= GRACE * 3);
    }

    #[test]
    fn nothing_can_be_held_once_closed() {
        let activity = Activity::new();
        activity.wait_until_idle_for(Duration::ZERO);
        assert!(activity.client().is_none());
    }
}
