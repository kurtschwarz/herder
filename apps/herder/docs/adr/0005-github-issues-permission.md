# 0005. The GitHub App reads issues

Status: accepted. Tracking issue: #144.

## Context

"From issue" on the New order card lists a repository's open issues and starts an agent from the one the user picks. That needs the issue's title, body and comments, which the Herder GitHub App ([0003](0003-github-pull-requests.md)) cannot read: its repository permissions are Pull requests (read) and Metadata (read) only.

## Decision

- **Add Issues: Read-only to the App.** Nothing else changes. The App still cannot write, and still needs no client secret, private key or webhook. This is the only permission added for the feature; Herder does not comment on, label or close issues.
- **Installations approve it one by one.** GitHub does not apply a new permission to existing installations. Each owner gets a request to review it, and until they approve, every call for issues on their repositories is refused with `FORBIDDEN`. herderd reports that as a new status, `permissionMissing`, apart from `notAccessible` (the App is not installed, or the user cannot see the repository), so the app can say what to do: open the installation's page and approve. A repository whose owner has not approved still shows pull requests as before.
- **A maintainer does the registration.** Changing the App's permissions is a step only its owner can take, so it is a checklist item in [the registration doc](0003-github-app-registration.md) and not something the build does. Code and tests run against stubs before it is done; testing against real GitHub waits for it, and for an approval on the installation used.
- **Read through herderd, in memory.** Issues are fetched by the daemon with the token the app hands it, as pull requests are. The list is cached in the daemon's memory only, per repository, tab and signed-in user, and dropped when the token is cleared or replaced. Nothing is written to disk. The body and comments of one issue are never cached: they are fetched fresh when an agent starts from it, so the prompt is what the issue says at that moment.
- **Protocol 6.** Four additive messages: `issue_query` and `issue_detail`, each with its response. No existing message changes, so `MIN_PROTOCOL` stays at 2.

## Consequences

- Until the App has the permission, "From issue" shows an explanation, not a list, for every repository.
- A user who signed in before the permission was added keeps a token that lacks it for as long as the installation has not approved; approval takes effect without signing in again.
