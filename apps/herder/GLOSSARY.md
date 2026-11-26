# Herder

The words this app uses for its own parts. Each is one thing: if the code or a conversation uses another word for it, one of them is wrong.

## Task Manager

**Task Manager**:
The one window, opened from Tools ▸ Task Manager, that lists every process Herder is running and what each is using. It reads the system on a timer for as long as it is open and not at all otherwise.
_Avoid_: Activity Monitor (it is not that app), process list.

**Process group (row)**:
A heading row in the Task Manager's table that holds other rows and shows their subtotals: Agent Sessions, Herder, and under Herder, Terminals and Other. It never moves when rows are sorted. Not an OS process group; a process that Herder starts is under the tab that started it, whatever group the OS puts it in.
_Avoid_: section, category.

**Running process registry**:
The app-wide list of tabs that have a process running, in every window: each agent session and each terminal, with the pid it started, its title, and a way to bring it forward. Windows write it as their processes start and end, and the Task Manager reads it to know which processes belong to which tab. Not the list of agent sessions (that is the sidebar's, and includes ones with no process).
_Avoid_: process table, tab list.

## Daemon

**herderd**:
The one local process that owns every agent session and terminal process, so they keep running when the app quits, crashes or updates. The app is its client. Not the app's own child: it is started in its own session and outlives the app.
_Avoid_: helper, agent host, background service.

**Reattach**:
Connecting a tab to the process herderd still has running for it, and showing the screen as it was. Nothing is started. Distinct from *resume*.
_Avoid_: reconnect, restore.

**Resume**:
Starting a new process with an agent's resume command, so the agent picks the conversation back up. Today what a relaunch does; once herderd owns the processes it is only for a session whose process has ended.
_Avoid_: reattach, restart.

## Editor

**Diff base**:
The revision whose merge-base with `HEAD` the editor compares the working copy against, for the gutter's change markers and the empty editor's changed-files list. Remembered per worktree; defaults to `HEAD`, which the picker calls Uncommitted. A stored ref that no longer resolves is kept, and `HEAD` is used until it comes back.
_Avoid_: base branch (that is what a new session is cut from), compare target.

**Selection prompt**:
The overlay that opens on the editor's selection with ⌘L, from which a code ref and some feedback are typed into an agent session in the same worktree. Anchored to the selected lines, it scrolls with them; unsent feedback is kept in memory per buffer. Herder can only reach an agent by typing into its terminal, so what it sends is pasted text.
_Avoid_: popover (it is not an `NSPopover`), inline chat.

**Code ref**:
A pointer at whole lines of a file, in the form an agent reads: `@path#L10-12`, with the path relative to the worktree, else absolute, and quoted if it has a space. For a buffer with unsaved edits, whose line numbers the disk would not match, it is `path:10-12 (unsaved)` followed by the lines in a fenced block.
_Avoid_: mention, link, snippet.

**External tab**:
An editor tab for a file outside every workspace, such as `settings.json`. It belongs to the window, not the workspace: it stays through a switch, works with no workspace open, is watched on its own and is not reopened after a relaunch. It has no git gutter, no file-tree reveal and no selection prompt.
_Avoid_: outside file, global tab.

## Settings

**User settings**:
What the user has chosen, held in `~/.config/herder/settings.json` (or under `$XDG_CONFIG_HOME`) and described by `settings.schema.json`: the update toggle, the first-prompt template, custom agents and the Anthropic endpoint. Edited in the Settings window or the file, which are two views of one value. Never holds a secret. Distinct from *app state*.
_Avoid_: preferences, config.

**App state**:
What the app remembers about itself so a relaunch lands where the last quit left off: windows, workspaces, tabs, history, the agent used last. JSON snapshots behind `StateStore`, with no schema, and never edited by the user.
_Avoid_: settings, preferences.

## Orders

**New order**:
The card at the top of the sidebar where a session is started from a prompt. Typing what to build and pressing Plan it fetches the default branch, names the work, cuts a worktree for it and starts the last-used agent there in plan mode with the typed text as its first message. Replaces the Plan, Build and New session buttons; the new-session modal is still behind the card's terminal icon.
_Avoid_: quick start, launcher.

**Naming call**:
The one request a New order makes to an Anthropic-compatible endpoint (Meridian by default) for a type (`feat`, `fix` or `chore`), a kebab-case slug and a title. Everything is named before the worktree exists, so nothing is renamed or moved afterwards. If it fails or takes about 4 seconds, the branch is `chore/<adjective>-<noun>` and the session is named from the start of the prompt.
_Avoid_: auto-name, rename.

**From issue**:
The New order card's other way to start: it opens the Implement an issue modal, listing the open issues of the card's workspace. Picking one cuts a worktree on `issue/<number>-<slug>`, named on this machine with no naming call, and starts the chosen agent in plan mode with the issue's title, link, body and latest comments as its first message. The session remembers the issue, and an issue with a session that has not ended is "in progress": picking it opens that session.
_Avoid_: import issue, issue picker.

## GitHub

**GitHub connection**:
The app's one signed-in GitHub account, made from Settings with the Herder GitHub App's device flow. The app keeps its tokens in one Keychain item and refreshes them; herderd is handed the current access token, holds it in memory only, and confirms it works by asking GitHub who it belongs to. It is what linked pull requests read through. Not a git remote or a credential for `git` itself.
_Avoid_: GitHub login, GitHub account (the account is who it is connected as), OAuth.

**Linked pull request**:
The pull request GitHub has for a session's branch, saved on the session (`AgentSession.pullRequest`) with its number, link, title, state (open, merged, closed), whether it is a draft, and when it was merged and last updated. Found by branch, so every session of that branch in the repository gets it; only same-repository pull requests count, not ones from forks; and it is the most recent, so a newer one replaces it. Shown as a `#123` badge, coloured by state, next to the branch in the agent header and on the session's row in the sidebar. Herder stops asking about a branch once its pull request is merged or closed.
_Avoid_: PR link, PR status.

