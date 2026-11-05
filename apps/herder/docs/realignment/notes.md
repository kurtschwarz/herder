# Realignment notes

Things spotted while moving code that are **not** part of the move. Rule 3 of
`../REALIGNMENT.md`: write it here and keep going.

Each entry says what, where, and why it was left alone.

## From Phase 0 (survey)

Phase 0 changed no code. The survey's §10 held open questions, all since answered
as D1–D10 in the plan.

- **`WorkspacesModel` reaches `UserDefaults.standard` directly** for
  `collapsedWorkspaces`, `selectedWorktreePath` and `selectedWorktreeWorkspace`
  (`Features/WorkspacesFeature/WorkspacesModel.swift`). It is injectable and
  defaulted, so it is testable, but it is persisted state not behind a service.
  Phase 4d is where it belongs.
- **`default.profraw`** is written into the repo root and `apps/herder/` by coverage
  runs and is not gitignored. Phase 8.

## From Phase 2 (Core, Services, TestSupport)

- **Three sets of preview doubles now duplicate the fakes.** Features depend on
  `TestSupport` from this phase on, so the hand-rolled doubles in
  `ExplorerFeature/ExplorerView.swift` (`PreviewGit`, `PreviewWatcher`,
  `PreviewFiles`) and in `AppFeature/Previews/PreviewClients.swift`
  (`PreviewFileClient`, `PreviewBookmarkClient`, `PreviewGitClient`,
  `PreviewFolderPickerClient`, `PreviewFileWatcherClient`) can mostly go, in
  favour of `StubGitClient`, `InMemoryFileClient` and friends. About 130 lines.
  Left alone here because deleting them changes what previews show, and this
  phase was meant to move code rather than change it. Do it in Phase 5, per
  feature, where the previews are being reworked anyway.
  `PreviewClients.previewContainer` cannot move to `TestSupport`: it needs
  SwiftData, which `TestSupport` may not import.
- **Four suites test the fakes, not the services.** `InMemoryFileClientTests`,
  `InMemoryBookmarkClientTests`, `StubGitClientTests` and
  `StubFolderPickerClientTests` landed in `ServicesTests` because that is where
  the rest of `ClientsTests` went. They belong in a `TestSupportTests` target, or
  beside the protocol they stand in for. Cosmetic; left for Phase 8.
- **`NoSyntaxHighlighter`'s test is in `ServicesTests`.** Same reason, same fix.
- **`InMemoryFileClient.seedUnreadable` discarded a `withLock` result**, which
  warned as soon as `TestSupport` started being compiled into the app build.
  Fixed in place with `_ =` rather than logged, because the definition of done
  says no new warnings and this one was a one-character fix.
- **The `Live*` prefix is now redundant.** `Services/Git/LiveGitClient.swift` is
  the only `GitClient` implementation in a module whose whole job is
  implementations; the prefix existed to tell it apart from the protocol when the
  two shared a target. Renaming is Phase 3 task 1's call, flagged here so it is a
  decision rather than an oversight.
- **`Storage` still imports `Core` and is imported by a feature.**
  `WorkspacesFeature` depends on `Storage`, so SwiftData is one hop from a
  feature. That is what Phase 3 task 4 (`RepositoryStore`) and Phase 4e exist to
  fix; the boundary check for it stays commented out until then.
