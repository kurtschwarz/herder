# herderd

The daemon that owns Herder's agent sessions and terminal processes. The decisions behind it are in `apps/herder/docs/adr/0001-herderd.md`; read that before changing the protocol or the lifecycle.

- `frame`, `protocol`, `session` and `idle` are portable and take any `Read`/`Write`. Do not let a socket type, or anything macOS-only, into them. `transport` is the one module that knows the connection is a local Unix socket.
- A protocol change is additive: new messages and new fields. Never change what an existing one means, and raise `MAX_PROTOCOL` only when something is added. Raise `MIN_PROTOCOL` only when an old app can no longer be served at all, which strands users on a daemon they cannot talk to.
- Every record the protocol names for a session or worktree carries a `HostId`.
- Git lives in `git/` and reads repositories with `gix`. Only `git/cli.rs` may run the `git` CLI, and it lists each operation that does and why. See `apps/herder/docs/adr/0002-git-in-herderd.md`. Its tests in `tests/` build fixtures with the real `git`.
- `just test` runs the tests and clippy.
