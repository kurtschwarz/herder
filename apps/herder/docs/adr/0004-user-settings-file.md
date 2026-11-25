# 0004. User settings move out of `StateStore` into `settings.json`

Status: accepted. Tracking issue: #136.

## Context

Everything Herder kept went through `StateStore`: JSON snapshots under Application Support, with no schema and no migration beyond `decodeIfPresent`. That rule suits app state. Windows, workspaces, tabs and history are written by the app, read by the app, and nobody else looks at them; a field that cannot be read is dropped and the app carries on.

The values the Settings window edits are different. They are the user's choices: the first-prompt template, custom agents, the Anthropic endpoint and the update toggle. People want to edit them as text, copy them between machines and keep them in dotfiles, the way Zed's `settings.json` works. Kept as snapshots, they had none of that. The snapshot keys are internal camelCase, the file sits next to bookmarks that must never be hand-edited, and nothing describes what a valid value is.

## Decision

- **A user-editable file.** User settings live in `~/.config/herder/settings.json`, or `$XDG_CONFIG_HOME/herder/settings.json` when that is set. The Settings window and the file are two ways to edit one value, `UserSettingsStore` in Core. `AgentCatalog` and `NamingSettings` read and write through it.
- **App state stays where it is.** The last-used agent, windows, workspaces, tabs and history stay in `StateStore`. The "no schema, no migration" rule still covers them, and covers app state only.
- **Sparse, strict JSON.** The file holds only values that differ from the default. A missing key, object or file is the default. Every write re-serializes the whole file, pretty-printed, with sorted keys, so `$schema` comes first. Comments are not kept, so JSONC is deferred.
- **Frozen names.** Keys are `snake_case`, nested by Settings pane, and once released they are frozen like a `persistenceKey`. Fields are only added. Unknown keys are ignored, so a file written for a newer build still reads.
- **A published schema.** `apps/herder/settings.schema.json` is written by hand, with descriptions, defaults and enums, and every file points at it on `main` through `$schema`. The path is frozen for that reason. The app carries no copy and no JSON Schema library: a drift test in `CoreTests` reads the schema from the repository and checks its properties against the `CodingKeys` and its defaults against what the app writes.
- **Live in both directions.** The store watches the file's folder, not the file, so an editor that saves by atomic replace is still heard. A change that reads back as the text last seen, such as our own write, is ignored. Writes from the window are debounced by 300 ms in the store; the file client does not debounce.
- **Errors keep the last good value.** Malformed JSON, a field of the wrong type, or an agent id that is invalid, a duplicate or a preset's leaves the settings in force as they were. The Settings window and the file's editor tab both say what is wrong. Such a file is never written over, because it is somebody's edit in progress. Changes made in the window apply until the file is fixed, then the file wins, so they are not saved.
- **Agent ids are readable.** Each custom agent has a required `id` matching `^[a-z0-9-]+$`, made from the name it was added with and kept through a rename, because the last-used agent, saved tabs and the session history name agents by id. Ids minted before this were `custom-` and an uppercase UUID. They move into the file lowercased, and `AgentCatalog.agent(_:)` still finds them by the old spelling.
- **Secrets never go in the file.** The Anthropic API key and the GitHub tokens stay in the Keychain. A secret in a dotfile is a secret in somebody's public repository.
- **The update toggle is the file's.** The app pushes it into Sparkle. Sparkle no longer decides it.
- **Migrated once.** On the first launch with no file, the template, the custom agents and the endpoint are read from the `agents` and `naming` snapshots and the toggle from Sparkle, and the file is written only if any of them differs from its default. A `settings-migration` snapshot records that this has happened, so a file the user deletes later stays deleted, and every setting stays at its default. The old fields stay on disk, unused. No key is renamed or deleted.
- **Opened in Herder's editor.** A button on every Settings pane opens the file as an external tab in the last main window that was key, or in a new one. External tabs are a general editor feature: they belong to the window, are not remembered, are watched on their own, and take a diagnostic banner the composition root connects to the store's error.

## Consequences

- There are two kinds of persistence, and a new field has to go in the right one. If a user would choose it in Settings, it is a user setting with a schema entry. If the app records it about itself, it is a snapshot field.
- A schema key is a public name. Renaming one breaks every file that uses it and every editor validating against `main`.
- The schema on `main` can be ahead of an installed build. Fields are only ever added, and unknown keys are ignored, so an older build reads a newer file without complaint.
- A comment typed into the file is lost the next time the Settings window writes it, until JSONC is supported.
