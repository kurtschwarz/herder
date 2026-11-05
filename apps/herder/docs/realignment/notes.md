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

## From Phase 2b (composition root)

- **The test scheme's name depends on the product count.** Reducing the package
  to one product renamed Xcode's generated scheme from `HerderKit-Package` to
  `HerderKit`, and `just test` failed with "does not contain a scheme". The
  justfile now says so at the recipe. A shared scheme checked into
  `.swiftpm/xcode/xcshareddata/xcschemes/` would make the name ours rather than
  Xcode's, at the cost of a chunk of version-coupled XML. Worth reconsidering if
  it bites again.
- **`AppEnvironment` takes a `ModelContainer` where `AppModel` took a
  `ModelContext`.** The scene needs the container for `.modelContainer(_:)`, and
  having both the app and the environment build their own would have been two
  sources of truth for the store. Tests that passed `ModelContext(container)`
  now pass the container and get `mainContext`, which is what the app always
  used.

## From Phase 3 (StateStore)

- **`BookmarkClient` does disk I/O synchronously**, on the main actor:
  `makeBookmark` and `resolve` both call through to `URL`'s bookmark APIs. Making
  them `async` cascades into `WorkspaceStore.open()` and then
  `AppEnvironment.start()`, which is how launch is sequenced. Phase 4f rewrites
  launch sequencing, so that is where this belongs. Recorded in the plan's Phase
  3 audit too, so it cannot be mistaken for an oversight.
- **A pre-existing `#require` warning surfaced** in
  `TreeSitterHighlighterTests` once the file was recompiled from scratch:
  `try? #require(tokens.first { ... })` followed by `.map`. Rewritten as
  `try #require(tokens.first(where:))` with the test marked `throws`, which is
  what it meant anyway. The code was byte-identical to before the realignment
  started, so the "zero warnings" baseline in the survey was measured against a
  cached build and was slightly optimistic. Both warnings are now gone.
- **Snapshot types must be `nonisolated`.** `StorageTests` defaults to
  `MainActor`, which isolates a nested struct's synthesized `Codable`
  conformance and leaves it unable to satisfy `StateStore`'s `Sendable`
  requirement. Harmless for the real snapshots, which live in `Core` with no
  such default, but worth knowing before writing a fixture in a `ui` target.

## From Phase 4a (the Workspace rename)

- **A `@MainActor` store in `Core` makes its test suite opt in.** Moving
  `WorktreeStateTests` from the `Worktrees` target (MainActor by default) into
  `CoreTests` (nonisolated by default) broke 28 call sites until the two suites
  were marked `@MainActor`. Worth knowing for 4b: every test that touches
  `Workspace` or `WorkspaceRegistry` from `CoreTests` needs it.
- **`Core` now holds both kinds of code**, nonisolated value types and two
  main-actor stores. That is what `ARCHITECTURE.md` asks for, but it means the
  module's isolation is no longer uniform and `swiftSettings: core` no longer
  tells the whole story. The annotations on `Workspace` and `WorkspaceRegistry`
  carry a note saying why they are explicit.
- **`WorkspaceRegistry` still holds exactly one live workspace** and stops every
  other on `select`. Unchanged by the rename, and the thing 4g changes.

## From Phase 4b (snapshots and UI state)

- **`WorkspaceServicesFactory` is still unwritten**, deliberately. The
  workspace-scoped services are the four clients `WorkspaceRegistry` already
  threads through to each `Workspace`. A factory earns its place when there is a
  search index or a PTY to build per workspace; until then it wraps nothing.
- **`AppSnapshot` does not hold the adopted repositories yet.** They are
  SwiftData rows until 4e, when they arrive as a new field with an empty
  default.
- **`Workspace.snapshot` has no `openTabs`.** Not an omission: there are no
  tabs. The field lands with the editor's tab model, and `decodeIfPresent` means
  state written before then still loads.
