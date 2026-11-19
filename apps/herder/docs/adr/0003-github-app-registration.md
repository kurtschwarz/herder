# Registering the Herder GitHub App

The checklist for the human step of [0003](0003-github-pull-requests.md). Do it once, as the owner of the `kurtschwarz` account (or the organisation that will own the App).

GitHub ▸ Settings ▸ Developer settings ▸ GitHub Apps ▸ New GitHub App.

## Details

- [ ] **GitHub App name:** `Herder`. Taken names get a suffix, and the name appears in the sign-in screen the user sees.
- [ ] **Homepage URL:** `https://github.com/kurtschwarz/herder`.
- [ ] **Callback URL:** leave empty. Device flow does not use one. (GitHub may insist on a value; use the homepage URL.)

## Identifying and authorizing users

- [ ] **Expire user authorization tokens:** on. Herder refuses a token that does not expire, because the whole refresh path assumes one that does.
- [ ] **Request user authorization (OAuth) during installation:** off.
- [ ] **Enable Device Flow:** on. Without it the first request answers `device_flow_disabled`.

## Post installation

- [ ] **Setup URL:** empty.

## Webhook

- [ ] **Active:** off. Herder polls through herderd; there is no server to receive a webhook.

## Permissions

Repository permissions only; leave Organization and Account permissions at No access.

- [ ] **Pull requests:** Read-only.
- [ ] **Metadata:** Read-only. GitHub selects this one itself.
- [ ] No events subscribed.

## Where can this GitHub App be installed?

- [ ] **Any account**, so that other users of Herder can sign in. "Only on this account" limits it to the owner.

## After creating it

- [ ] Copy the **Client ID** (it starts `Iv1.` or `Iv23`) from the App's page. It is public: do not generate a client secret, and do not generate a private key. Device flow needs neither.
- [ ] Put the client ID in `apps/herder/project.yml`, under `settings.base.HERDER_GITHUB_CLIENT_ID`, then run `just project` in `apps/herder`.
- [ ] Rebuild and open Settings ▸ General. The GitHub section shows "Sign in with GitHub". If it says the build has no GitHub App, the client ID did not reach `Info.plist`: check `HerderGitHubClientID` in the built app.
- [ ] Sign in with a real account. The code shown is entered at `github.com/login/device`; Settings should then say "Connected as @login".
- [ ] **Install the App** on the account and the repositories whose pull requests Herder should read (the App's page ▸ Install App). A signed-in user sees nothing of a repository the App is not installed on.
- [ ] Check the expiry settings by looking at the saved item: the Keychain item `ar.schw.herder.github` (`-dev` for a debug build) holds both expiry times, which should be about 8 hours and 6 months ahead.
