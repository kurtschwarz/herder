# 0002. herderd runs every git operation

Status: accepted and delivered. Tracking issue: #109. Supersedes the "Files, git and the file watcher stay in the app" bullet of [0001](0001-herderd.md); files and the file watcher still stay in the app.

## Context

The app reads repositories and runs `git` itself through `LiveGitClient`. Two things make that the wrong place. Git has to run where the repository lives, and once a host other than this machine exists, that is not the app's process. And the daemon is meant to be the one source of repository state, which it cannot be while the app keeps its own.

## Decision

Every `GitClient` method is answered by herderd. The app asks; it runs no `git` process and reads no `.git` directory.

- **Engine.** `gix`, in `packages/herderd/src/git`, which is portable like the rest of the daemon's core. Where `gix` cannot match what `git` prints, that one operation calls the `git` CLI, and only from `git/cli.rs`. That file lists every fallback and why, so the list is in one place. Expected: `addWorktree`, and the diff-against-working-tree pair (`changedFiles(since:)`, `shortstat(since:)`), because `gix` has no combined staged-plus-unstaged diff and its rename pairing can differ from `git diff -M`.
- **Protocol.** A generic envelope: `git_request {id, op, ...}` and `git_response {id, result | error}`, with the arguments of an `op` beside it in one flat object. Paths are strings on the daemon's host. Errors are typed (`code`, `message`). Records carry `HostId`. It is additive, and `MIN_PROTOCOL` and `MAX_PROTOCOL` both rise to 2, the version that added git: nothing used the daemon before, so no older app needs serving and there is no version-skew handling. An old daemon shows as incompatible in Settings ▸ General.
- **The app side.** `DaemonGitClient`, bound to one host, is chosen in `AppEnvironment`. The `GitClient` signatures do not change, so Core, the features and the fakes are untouched. There is no fallback to running git in the app: if the daemon is unreachable after the existing connect-or-spawn retry, a call throws `GitClientError.commandFailed("herderd is not running")`. Each request is its own connection (handshake, request, reply, close), so requests run side by side with no tying of replies to requests in the app; `id` still lets a multiplexed transport do that later.
- **Logic moves with the engine.** The daemon owns default-branch resolution and the status and diff parsing, so `GitDefaultBranch` leaves Core. `GitWorktreeLocation` and `GitRefName` stay in Swift, because the UI uses them before any request is sent.
- **`gitDirectory`** returns a host path. The app watches it only when the host is `local`; watching a remote host's files is out of scope.
- **Runtime.** Each connection serves git requests on a pool of four workers. There is no cancellation, and no caching or coalescing of `status`, until a measured problem asks.
- **Tests.** A Rust integration suite that builds fixtures with the real `git` CLI is the contract. The Swift `DaemonGitClient` runs the same scenarios against a live `herderd`. The scenarios of the old `LiveGitClient` tests are the spec, and none are dropped.

## What was delivered

It was built as five slices, each carrying its share of the ported scenarios: the envelope and `repositoryKind`; the disk-read operations (`worktrees`, `branches`, `gitDirectory`, `checkout`); `status`; the diff and history operations; and `addWorktree`, after which `LiveGitClient`, `GitDefaultBranch` and the Swift-side parsing were deleted.

The `git` CLI fallbacks, all in `git/cli.rs` with the reason beside each:

- `addWorktree`: `gix` cannot create a linked worktree.
- `shortstat`, and `changeSummary` which ends in it: `gix` has no combined staged-plus-unstaged diff of the working tree against a commit.
- `changedFiles`: the same, and `gix`'s rename pairing can differ from `git diff -M`.

Everything else, including `status`, is `gix`. Two small differences from the old behaviour are deliberate: an annotated tag is dated by the commit it points at, where `git for-each-ref` left it undated, and branch and file order uses a natural compare in Rust in place of `localizedStandardCompare`.

## Consequences

- `gix` is a dependency of a bundled, signed binary, built with `default-features = false` and only the `sha1`, `status` and `revision` features. The universal release binary is about 10.7 MB.
- The `git` CLI is still needed on the daemon's host for the fallbacks above.
- Git operations now fail when the daemon does. The daemon is already something the app must reach for sessions, so this adds no new way to be broken, only one more thing that notices.
- `status` stays a request per call with no cache. A watcher-driven burst makes a burst of requests; the pool bounds the work, not the number of requests.
