# 0003. GitHub connection: the app signs in, herderd is handed the token

Status: accepted. Tracking issues: #111 (the GitHub connection) and #112 (finding and linking pull requests, in the last section).

## Context

Herder is to show the pull request a worktree's branch belongs to. That needs a GitHub credential, a place to keep it, and a process that talks to GitHub. Git already runs in herderd ([0002](0002-git-in-herderd.md)), so herderd is where the pull request queries will run, and it has to be given the credential by something that can sign a user in.

## Decision

- **A GitHub App, not an OAuth App.** Its permissions are Pull requests (read) and Metadata (read), device flow is on, user-to-server tokens expire, and webhooks are off. An OAuth App's scopes are coarse (`repo` reads and writes code), its tokens do not expire, and it cannot be limited to the repositories a user installs it on. Herder ships the App's client ID, which is public; device flow needs no client secret, so there is none to ship. The client ID is a build setting, `HERDER_GITHUB_CLIENT_ID`, read from `Info.plist`, so the code is built and tested against stubs before the App exists. A build without one says so when the user tries to sign in.
- **The app runs sign-in.** Device flow and token refresh use `URLSession` in the app (`LiveGitHubAuthClient`). [0002](0002-git-in-herderd.md) covers git only, so these calls do not conflict with it. Signing in needs a user in front of a window, which herderd does not have.
- **The app owns the tokens.** The access token, the refresh token and both expiry times are one Keychain item (`KeychainGitHubTokenVault`), under a service name that differs in a debug build. herderd never reads the Keychain. There is one account in v1.
- **Token lifetime.** The app refreshes about five minutes before the access token expires, and at launch if it already has, or is about to. GitHub honours a refresh token once, so the new pair is saved to the Keychain before anything else is done with it. If GitHub cannot be reached, the app keeps the tokens and tries again a minute later. If the refresh token has expired or GitHub refuses it, Settings shows "Reconnect GitHub". If GitHub refuses an access token the app thinks is good, it refreshes once and, failing that, asks for a reconnect.
- **Handing the token over.** Three additive messages on the existing 0600 socket: `set_github_token`, `clear_github_token` and `check_github`, each answered by a `github_response` carrying the same `id` and a `check`. `set_github_token` stores the token and then checks it, so its answer says whether it works. The daemon stores and forgets tokens in the order a connection's messages arrive, on the connection's reading thread, so a set followed by a clear leaves nothing held; only the check runs on a worker. The app sends the token at launch and after every refresh, and `clear_github_token` on sign-out. herderd keeps it in memory only: nothing is written to disk, and each request is its own connection, so it lives in a process-wide store rather than a connection's state. A daemon that exits idle forgets it; the app, which holds a connection while it runs, is what keeps it from exiting. A daemon that dies under a running app comes back without the token, and the app only resends it at its next refresh or when the user chooses Check Again. Resending on every reconnect is left for when something needs the token between refreshes.
- **The check.** herderd runs a GraphQL `viewer { login }` query with the token. The answer is `ok(login)`, `unauthorized` (a 401), `not_connected` (no token held) or `error(message)`.
- **Protocol 3.** Raising `MAX_PROTOCOL` from 2 to 3 is additive: the daemon still serves an app that speaks 2, so `MIN_PROTOCOL` stays at 2. The app's range is 3 to 3, so a newer app that meets a version-2 daemon takes the existing `incompatible` path of 0002: if that daemon owns no sessions it is ended and the bundled one started.
- **HTTP in herderd: `ureq` with rustls.** A hand-written GraphQL query and `serde` structs. No tokio, which the daemon does not otherwise use, and no `octocrab`, which brings an async runtime and a client for an API of which this needs one query. `ureq` is blocking, which fits the daemon's worker threads. The GraphQL endpoint is a parameter, so tests point it at a stub server on a local port.

## Security

The access token is a bearer credential: whoever holds it can read what the user can on the repositories the App is installed on.

- **It is never returned.** No daemon message carries a token, so a client of the socket can store one but never read it back. `Secret` in the protocol prints as `<redacted>` in `Debug`, so a logged message, a panic or an `unwrap` cannot show it. Error messages are built from fixed words and what GitHub said, and any occurrence of the token in them is replaced before they leave the daemon. The daemon logs nothing about requests.
- **Who may send it.** The socket is mode 0600 and the daemon refuses any peer that is not the same user, so only processes of this user can set or replace the token. Such a process could already read the app's memory, or the Keychain item if the user allowed it.
- **Why the Keychain is the app's.** The refresh token lasts about six months and mints new access tokens, so it is the one worth protecting. It stays in the app's Keychain item and is never sent anywhere but GitHub. The daemon holds only the access token, which lasts eight hours.

Future hardening, not in scope: herderd could verify each client's code signature before accepting a token, so that only a signed Herder build could set one. The 0600 socket and uid check would then be one layer of two.

## Consequences

- herderd's binary gains `ureq` and `rustls`, about 4 MB: the universal release binary went from 11.7 to 15.5 MB.
- herderd is the first thing in the daemon that makes a network request. `github.rs` is the only module that does, and it is not part of the portable core.
- Sign-in needs the human step of registering the App and putting its client ID in `project.yml`: see [0003-github-app-registration.md](0003-github-app-registration.md).

## Linked pull requests

Tracking issue: #112. A session's branch is looked up on GitHub, and the pull request found is saved on the session (a **linked pull request**, `AgentSession.pullRequest`) and shown as a `#123` badge.

### Decision

- **Where the repository comes from.** herderd reads `remote.origin.url` with gix, in `git/remote.rs`, and parses the owner and name of a github.com remote (https, `git@` and `ssh://`). Only github.com is supported, and only pull requests whose head branch is in the same repository: a pull request from a fork is dropped. A folder whose `origin` is anything else, or missing, has no entry in the answer and is not an error.
- **The query.** One GraphQL request per poll covers every watched repository and branch: an alias per repository, and inside it an alias per branch on `pullRequests(headRefName:, first: 5, orderBy: {field: CREATED_AT, direction: DESC})`, with `headRepository` to filter forks. Owners, names and branches are GraphQL variables, never part of the query text. It reads five pull requests rather than one so that a fork's newer pull request from a branch of the same name cannot hide the repository's own; the newest same-repository one wins. `defaultBranchRef` rides in the same request, so herderd can say which branch is the default and give it no pull request, and the app can stop asking about it.
- **Transport is app-driven polling**, because herderd cannot push events yet. A loop in the app (`LinkedPullRequests`, on a `ClockClient`) sends `pull_request_query` and gets a `pull_request_response`. herderd keeps an in-memory cache and nothing on disk. Protocol 4 adds the two messages; an app that speaks 2 or 3 is still served, and `MIN_PROTOCOL` stays at 2.
- **The answer** has, for each repository, a status (`ok`, `not_accessible`, `unauthorized` or `error`), `owner/name`, the default branch when known, and for each branch its pull request or none.
- **Failures.** On a network error, a 5xx, a 403 or 429, or GraphQL's `RATE_LIMITED`, herderd answers with what it last heard, with status `error`, and tells the app to wait longer: `next_poll_seconds` is 60, doubling with each failure in a row up to 600, and is 60 again after a success. The wait is herderd's to say, so a second window or a restarted app cannot undo it. A 401, or no token, is `unauthorized`: it does not slow the poll. The app then runs the one refresh the GitHub connection already has (`GitHubConnection.recheck()`), and shows "Reconnect GitHub" if that fails. Errors are shown in Settings and nowhere in the session UI. A herderd that cannot be reached is backed off the same way by the app.
- **Which branches are watched** (`AgentSessions.watchedBranches()`): those of sessions that have not ended, and of ended sessions whose linked pull request is still open; not a detached checkout, whose recorded branch is a short commit; not the default branch, once herderd has said which it is; and not a branch whose pull request is merged or closed. Only repositories whose history has been loaded are covered, which is the ones the sidebar lists.
- **What a pull request is attached to.** The pull request is found by branch, and written to every session in that repository whose `branch` matches, ended or not. A branch that has no pull request leaves a session's link as it was.
- **Saved data.** `AgentSession.pullRequest` is optional, read with `decodeIfPresent`, and saved in the session history file. It holds `number`, `url`, `title`, `state`, `isDraft`, `mergedAt` and `updatedAt`. A state this build does not know decodes as `unknown`, as `EndReason` does. There is one field: a reopened pull request updates it in place and a newer one replaces it.
- **Repositories the App cannot reach.** If the GitHub App is not installed on a repository, GitHub answers with `null` for it, and Settings lists it as "not accessible" with an "Install app" link (`GitHubApp.installURL`, which assumes the App's slug is `herder`).

### Limitations

- **Nothing is checked while the app is closed.** The first poll after launch catches up.
- **Renaming a branch breaks the link.** `session.branch` is saved once, when the session starts, and never updated, so the old name is what is asked about. A branch that is reused for a new pull request after the first was merged is not looked at again either, since its session stopped being watched.
- **A poll that finds nothing to watch is looked at again after five seconds**, locally. The first poll after a session starts can be a minute away.
- Nothing notifies the user and nothing happens automatically on a merge. Recording the merge (`mergedAt`, state) leaves room for both.
