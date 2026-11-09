# opencode-plugin-osc-7501

An opencode v2 TUI plugin that tells the terminal what the session on screen is
doing, with the program status protocol (OSC 7501). It is how Herder's sidebar
knows an opencode session is working or waiting: Herder reads nothing else.
The protocol is at <https://www.superlogical.com/rex/docs/build/program-status>.

Herder's app bundle carries `tui.ts` and `status.ts` under
`Contents/Resources/opencode/plugins/osc-7501`. At launch the app links that
folder into `~/.config/opencode/plugins/osc-7501`, where opencode finds
plugins. A file added here that the plugin needs has to be added to the
app's `project.yml` too. `just install` links this folder there instead, so
an edit here reaches the next opencode started. The app leaves a link it did
not make alone. It only reports when `TERM_PROGRAM` is `Herder`, which Herder sets for
everything it runs; the `always` option turns that check off.

## What it reports

One record, the root, for the session on screen and its subagents together:

- `blocked`, kind `permission`: a permission request is waiting. The message is
  the request's own, or its action and resources.
- `blocked`, kind `question`: a form is waiting. The message is its title.
- `working`: any session in the family is running.
- `error`: the last run failed, with opencode's message.
- `done`: the last run finished. An interrupted run is `idle`, as the spec asks.
- `idle`: anything else, and the home screen.

Waiting on the person beats working, which beats how the last run ended. It
writes only when the report changes, and clears everything when it stops.

## How it writes

The renderer draws on a thread of its own. A plain `process.stdout.write` can
land inside one of its escape sequences and garble a frame, which a test against
opencode 2.0.16 caught once in about ten thousand reports. The renderer's
`writeOut` queues bytes behind its frames, and in the same test none landed
inside one. It is private in OpenTUI's types, so the plugin falls back to
stdout when it is gone. If an opencode update leaves stray characters on screen,
check `writeOut` first.

## Files

- `status.ts`: what a session is doing, and the report that says so. No
  opencode imports, so `just test` runs it on Node alone.
- `tui.ts`: the plugin. Reads opencode's data on every event, and on a timer
  for switching sessions, which is not an event.
