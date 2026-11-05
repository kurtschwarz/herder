# Realignment notes

Things spotted while moving code that are **not** part of the move. Rule 3 of
`../REALIGNMENT.md`: write it here and keep going.

Each entry says what, where, and why it was left alone.

## From Phase 0 (survey)

Nothing yet — Phase 0 changed no code. The survey's §10 holds the open questions
that need a decision rather than a follow-up.

Two candidates for follow-up once the structure settles:

- **`WorkspacesModel` reaches `UserDefaults.standard` directly** for
  `collapsedWorkspaces`, `selectedWorktreePath` and `selectedWorktreeWorkspace`
  (`Features/WorkspacesFeature/WorkspacesModel.swift:27`). It is injectable and
  defaulted, so it is testable, but it is persisted state not behind a service.
  Phase 4's `PersistedWorkspaceUIState` is where it belongs.
- **`default.profraw`** is written into the repo root and `apps/herder/` by coverage
  runs and is not gitignored.
