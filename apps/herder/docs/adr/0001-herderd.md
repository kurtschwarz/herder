# 0001. herderd owns agent sessions and terminal processes

Status: accepted. Tracking issue: #85.

## Context

The app owns every PTY. When it quits, crashes or updates, the agents it started are orphaned: `AgentMark` and the leftover-agent sweep exist to clean up after that, and a relaunch resumes a session with the agent's resume command instead of reattaching to the process that was running.

## Decision

A local daemon, **herderd**, owns every agent session and terminal process. The app is a client: it starts or finds the daemon, connects, and reattaches each tab to its live process.

- **Portable Rust**, in `packages/herderd`, beside the syntax highlighter. Nothing in the daemon's core is macOS-only; an OS-specific backend (libproc on macOS, `/proc` later) sits behind an interface when the process tree is added.
- **A framed protocol over any byte stream.** A frame is a big-endian `u32` length and that many bytes, at most 16 MiB. Payloads are JSON tagged by `type`. The first frame on a connection is the client's `hello`, which carries the range of protocol versions it speaks, and the daemon answers `welcome` with the version chosen or `incompatible` with its own range. Locally the stream is a Unix domain socket, mode 0600, with the peer's uid checked by `getpeereid`. `frame`, `protocol` and `session` take any `Read`/`Write`, so an SSH `--stdio` transport needs no change to them. `herderd --stdio` already serves one connection that way.
- **Terminal output goes through the protocol**, with backpressure. Passing the PTY descriptor with `SCM_RIGHTS` is allowed only as a local fast path, never the only path.
- **Records carry a host.** Every session and worktree the protocol names carries a `HostId`, with `local` as one host, so a remote host later does not migrate persisted keys. `welcome` already names the daemon's host.
- **The daemon is the only thing on a host that starts or ends agent and terminal processes.** Files, git and the file watcher stay in the app.
- **The app keeps its seams.** `PTYClient` and `ProcessMonitorClient` gain daemon-backed implementations, chosen in `AppEnvironment`. Core, the features and the fakes do not change.
- **Screen state lives in the daemon**, with libghostty-vt hosted in Rust, so a reattached tab shows what was on screen.

### Lifecycle

**The app spawns it on demand**, rather than registering it with launchd through `SMAppService`.

The app first tries to connect to the socket. If nothing answers, it starts the copy bundled at `Contents/MacOS/herderd` with `posix_spawn` and `POSIX_SPAWN_SETSID`, output discarded, and retries the connection for a few seconds. A new session means a signal to the app's process group, including Ctrl-C in the terminal `just dev` runs in, never reaches it. The daemon refuses to start if something already answers on its socket and replaces a socket left by one that died.

Why not launchd: an `SMAppService` agent needs a plist in the bundle, shows in System Settings ▸ Login Items, and is restarted by launchd after it exits, all of which are wrong for a daemon whose purpose is to hold sessions the user can see. It also makes a dev build and an installed release fight over one label. Spawning on demand needs none of that, and moving to launchd later changes only who starts the process.

A debug build and a release build use different sockets, `herderd-dev.sock` and `herderd.sock` in `Application Support/Herder/`, chosen by `#if DEBUG` in `LiveDaemonClient.socketName`. Each starts and talks to its own bundled daemon, so protocol changes under development are never tested against an installed daemon, and idle exit or session ownership in one never affects the other. Both can run at once.

Costs accepted: after a reboot or logout there is no daemon until the app is opened, which matches there being no sessions to keep. If the daemon is killed, its sessions are lost either way.

**When it exits.** It never exits while it owns a session or has a client connected. A daemon with neither for ten minutes (the idle grace period) exits by itself, so a user who stops using Herder is not left with a resident process. Any session or client cancels the countdown, and the last one leaving restarts it. Sessions do not exist yet, so today idle means no client; `idle::Activity` already counts both. `--idle-timeout SECONDS` shortens the period for tests.

The exit order is: stop accepting, remove the socket, exit. A client that connects after the daemon decided to close is refused rather than half served, and once the socket is gone the next app finds nothing and starts the bundled binary.

**How an old daemon goes away after an update.** Sparkle replaces the app and leaves the running daemon alone, so the old binary keeps answering the socket. Idle exit is what ends it: once the app has quit and the grace period has passed, the daemon removes its socket and the next launch starts the new bundled `Contents/MacOS/herderd`. A daemon that is busy (it owns sessions, or the app is still open) is not replaced; that is the live handoff, a later change that moves sessions to the new binary without ending them.

### Version skew

A Sparkle update replaces the app and leaves the running daemon alone, because restarting it would end every session. So a new app routinely meets an older daemon.

- The app sends the range of versions it speaks and the daemon picks the highest in common. The app uses features the chosen version has and none it lacks.
- Protocol changes are **additive**: new messages and fields. An existing message never changes meaning. `MIN_PROTOCOL` rises only when an old peer can no longer be served at all.
- The bundled binary is never swapped under a running daemon. A newer bundled daemon starts only when none is running.
- If there is no version in common, the app does not kill the daemon. Settings ▸ General shows both ranges. Offering to restart it is a later change and will only be offered when the daemon holds no sessions.

## Consequences

- `just build` and `just test` in `apps/herder` build the daemon first, as they do the syntax crate, and the app bundles the binary and signs it.
- Core gains `DaemonClient`, `DaemonStatus` and `DaemonWire` (the bytes of the protocol, with no I/O), and the live client is in `Services/Daemon`.
- `AgentMark` and the leftover-agent sweep are removed when the daemon owns the processes, not before.
- Running the daemon on a remote machine, a CLI client and a menu bar extra are not part of this decision.
