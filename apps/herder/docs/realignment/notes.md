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

## Incident: 4a stranded the store on disk (fixed)

`just dev` crashed on launch after 4a:

```
Cannot use staged migration with an unknown model version.
AppEnvironment.swift:65: Fatal error: Could not open the workspace store
```

**Cause.** 4a renamed the `@Model` class `Workspace` to `Repository`. A `@Model`
class name *is* the stored entity name — SwiftData derives the SQLite table from
it, and the store records the schema it was written against. The store on disk
has a `ZWORKSPACE` table recorded against a schema saying `Workspace`; after the
rename, `WorkspaceSchemaV1` described an entity called `Repository`, so the
store matched no version in the plan and SwiftData refused to open it at all.

The 4a commit claimed a pure rename with no behaviour change. That was wrong: it
was a schema change, and it made every adopted folder — and its
security-scoped bookmark, which cannot be regenerated — unreachable.

**Fix.** The persisted class keeps the name `Workspace` inside
`WorkspaceSchemaV1`, with `public typealias Repository` over it. The codebase
reads `Repository` everywhere, the store keeps the entity it recorded, and the
question disappears when the model is retired for snapshots in 4e.

**Why nothing caught it.** Every other storage test uses an in-memory
container, which is created at the current version every time, so it can never
disagree with the code. The first test written for this was no better: it built
its "V1 store" from today's `WorkspaceSchemaV1`, so both sides moved together
and it passed under the bug. A schema test is only worth anything against a
store the build did not write.

So `StorageTests` now carries `Fixtures/v1/Workspaces.store`, a real V1 store
with two repositories in it, copied somewhere writable per test and opened at
V2. Reintroducing the rename fails five tests with the same
`loadIssueModelContainer` the app hit. The fixture is committed on purpose; it
is generated by no test, because a self-regenerating fixture would just adopt
whatever the code currently says and pass.

**Loose ends.**
- A backup of the real store was taken before the fix and is still at
  `~/Library/Application Support/Herder/backup-20261105-194922/`. The live store
  has since migrated to V2 with its row and its 740-byte bookmark intact, so the
  backup can be deleted whenever Kurt likes. Not deleted here: it is his data.
- The `fatalError` now names the store path, says the data is intact, and says
  not to delete it to recover. Still fatal, which is deliberate — carrying on
  would invite the user to add folders to a store that is not there.
- **4e migrates these rows into snapshots**, which is the next time this risk
  peaks. The fixture test is the thing that makes that step safe to attempt.

## From Phase 4d (file tree expansion)

- **`expanded` is a computed property over the workspace's UI state**, not a
  stored one. Twelve readers inside `ExplorerModel` are untouched that way, and
  there is exactly one place the tree's expansion lives. It is silently
  unwritable when no worktree is shown, which is correct — there is nothing for
  a path to be relative to — but it is a quiet failure, so it carries a comment.
- **Expansion surviving a switch is not yet visible to the user.**
  `WorkspaceRegistry.select` still drops every workspace it is not showing, so
  the state goes with the object. The structural move is done and the behaviour
  arrives with 4g, or with 4f if a snapshot is saved and restored first. The
  test for it has to hold the `Workspace` across the switch for that reason, and
  says so.
- **`PathKey` is deliberately not `Codable`**, so `ExplorerUIState` encodes its
  keys as the path strings they already are. A synthesised `Codable` on `PathKey`
  would let a decoder hand one back without canonicalising, which is the one
  thing the type exists to prevent.

## From Phase 4c (per-window active workspace)

- **The previously selected worktree does not restore once, on the first launch
  after this change.** The selection moved from two global `UserDefaults` keys
  to `@SceneStorage`, so the old value is not where the new code looks. One
  empty sidebar selection, then it sticks. Not worth a migration for state the
  user replaces with a click.
- **`UserDefaults` is still in the feature** for `collapsed`. The selection keys
  are gone; the last one goes in 4f, when sidebar collapse moves to
  `AppSnapshot`.
- **`DesignSystem` now depends on `Core`.** Only to declare the `@Entry` for
  `OpenWorkspaceAction`: `Core` cannot, because it may not import SwiftUI, and
  putting the key inside a feature would make App import one feature to
  configure another. If a second action joins it, a small component module is
  probably the better home.
- **Deselection moved from the listing to the watcher.** `WorkspacesModel.refresh`
  used to clear the selection when git stopped reporting the worktree;
  `AppView` now watches `Workspace.isAvailable`, which the file watcher sets when
  the folder goes. Same outcome, sooner, and in one place — but it is a
  different mechanism, so it is worth a look during the smoke test: remove a
  worktree with `git worktree remove` while it is showing.
- **`AppView` is getting busy** — eight modifiers of app logic on one `HStack`.
  Fine for now; `WorkspaceView` in `ARCHITECTURE.md` is where this goes when the
  window gains a second thing to show.

## From Phase 4e (repositories off @Query)

- **`RepositoryStore` is state in `Core`, not a service behind a protocol.** The
  plan called for a `RepositoryStore` protocol in `Core/Services/`, but the
  seam was already there: the thing that varies is where the list is *stored*,
  and that is `StateStore`. A second protocol in front of the list itself would
  have had one implementation forever. The scoping table in `ARCHITECTURE.md`
  listed it as an app-scoped service and has been corrected.
- **I deleted 27 tests and had to go back for them.** Removing
  `SwiftDataRepositoryStore` took `SwiftDataRepositoryStoreTests` with it, and
  the test count dropping from 347 to 324 is what caught it. They are now
  `CoreTests/RepositoryStoreTests`, assertions unchanged except that a
  `Repository` is a value, so each one reads the result off the store rather
  than off the copy it is holding. Worth a rule: if a module is replaced rather
  than moved, its tests are ported before the old file goes.
- **Security-scoped bookmarks are now base64 inside JSON inside SQLite.** Fine
  today, and it makes D6's open question concrete: after Phase 7 they will sit
  in a plain JSON file under Application Support. A bookmark is a capability
  scoped to this app's identity rather than a secret, and Apple's own apps keep
  them in plists, so a file is defensible — but it is Kurt's call before Phase 7
  swaps the store.
- **Mutations save immediately rather than debounced.** `ARCHITECTURE.md` asks
  for a debounce; it is right for UI state, which changes as the user scrolls,
  and wrong here. Adding a repository mints a bookmark that cannot be
  regenerated, so losing it to a crash inside the debounce window is not worth
  the saved write. Debouncing arrives with the UI-state snapshots in 4f.
- **`AppEnvironment.start()` is `async` now**, and the window renders before it
  finishes, so the sidebar is empty for the moment the first read takes. `@main`
  calls it from `.task`, not `init`, because reading the list touches the disk.

## From Phase 4f (restoration)

- **There is no save at termination, and that is not an oversight.**
  `willTerminate` is a synchronous callback; `StateStore` is `async`. A `Task`
  started there races the process exiting, so `stop()` is deliberately sync and
  writes nothing. Workspace snapshots are written as UI state settles (~400ms)
  and whenever a workspace is switched away from, which leaves a small window:
  quit within 400ms of opening a folder and that folder is not remembered. The
  real fix is `applicationShouldTerminate` returning `.terminateLater`, which
  means an `NSApplicationDelegate` and is its own task.
- **Reading a feature's UI state creates it**, so merely rendering the file tree
  leaves an `explorer.expanded` blob — empty — in the snapshot. Harmless, but it
  makes `persistableUIState()`'s "a feature the user never opened has nothing to
  say" slightly optimistic: looked-at counts as opened. Not worth distinguishing
  until something expensive is stored.
- **Collapse went on `Repository` rather than into a `WorkspaceUIState`.** It is
  app-scoped, not per-workspace, and the alternative was a second writer to the
  `AppSnapshot` key — `RepositoryStore` already does read-modify-write there, and
  two writers to one key is how updates get lost. `order` was the precedent.
- **`Workspace` now takes a `StateStore`**, so every test that builds a registry
  needed one. Worth knowing before 4g touches the same constructor.

## From Phase 4g (several live workspaces)

- **`@SceneStorage` cannot be verified by killing the process.** macOS only
  writes window restoration state on a clean quit, so every `pkill`-based run in
  this realignment left it unexercised. The active-worktree-per-window restore
  is therefore the one piece of Phase 4 that only Kurt's smoke test can confirm
  — step 8, with ⌘Q.
- **A stale `collapsedWorkspaces` key is still in the app's preferences**, an
  empty array left behind when collapse moved onto the repository record in 4f.
  Inert, and it is the user's prefs rather than ours to clear, but it is cruft:
  Phase 8 should remove it on first launch or leave it documented.
- **Tests had to learn to say what is on screen.** A workspace nothing displays
  does not drain, so suites that drive the watcher now declare a window —
  `ExplorerModelTests` and `EditorModelTests` do it once in `init`, and
  `WorkspaceTests` has a `show(_:)` helper. A drain test that forgets this
  watches nothing happen and passes for the wrong reason, which is worth
  remembering when writing the next one.
- **Three tests asserted the old behaviour and were rewritten, not deleted.**
  `switchingWorktreeStopsWatchingTheOldOne` became
  `switchingWorktreeKeepsTheOldOneOpen` plus two about what a background
  worktree costs; `comingBackToAWorktreeKeepsWhatWasAlreadyRead` had been
  asserting the opposite of its own name, and now asserts the name;
  `comingBackToAWorktreeReplaysWhatItMissed` now closes explicitly, because
  replay only matters for a worktree that was actually put away.
- **Nothing closes a workspace except the folder vanishing or the app quitting.**
  There is no UI for it. That is fine while a workspace costs a watcher, and
  wants revisiting when one can hold an agent session.

## From Phase 5, Repositories

- **The UI still says "workspace" where the code now says repository.** The
  sidebar header is "Workspaces", the button and the modal are "Add workspace",
  and the empty state reads "No workspaces yet". Under rule 3 those are
  behaviour, so the rename stopped at the code and the strings were restored
  verbatim. They are now the only place in the app where "workspace" means a
  repository, which is exactly the collision D4 existed to remove — it wants a
  copy pass, and that is Kurt's call rather than a mechanical one. Five strings,
  in `RepositoriesView` and `AddRepositoryOverlay`.
- **`RepositoriesModel.isKnown(_:)` has no caller outside its tests.** 4c
  introduced it so a window could notice its worktree had been removed, and then
  solved that through `Workspace.isAvailable` instead. It is `internal` now, so
  it is dead code inside the module rather than unused API. Phase 8 either
  deletes it or the next feature that needs it finds it.
- **The feature's public surface is four names**, not everything it used to
  export: `RepositoriesModel` (with `init`, `isModalPresented`,
  `nameOfRepository(holding:)` and `beginAdding()`), `RepositoriesView`,
  `AddRepositoryOverlay` and `NewSessionOverlay`. `AddRepositoryModel` and
  `NewSessionModel` are internal; their tests already used `@testable`, so
  nothing had to change to allow it. The overlays stay separate from the view
  because `AppView` draws them past the sidebar's edge, over the whole window.
- **`AppEnvironment.repositoryList` reads oddly beside `repositories`.** One is
  the feature's model, the other the store it reads; the pair is
  `RepositoriesModel` + `RepositoryStore` spelled out, and `Sidebar` takes them
  as `model` and `store`. Worth a better name if a second app-scoped feature
  arrives.
- **One pre-existing warning fixed in passing**: `try?` on a
  `@discardableResult` call in `PreviewClients` still warns, because `try?`
  wraps the result in a new optional that `@discardableResult` does not cover.
  `_ =` in front of it. It predates this task but the bar is zero warnings.

## From Phase 5, FileTree

- **`persistenceKey` is data, not a name.** `FileTreeUIState` still persists
  under `"explorer.expanded"`, because the key is what the saved blobs are
  filed under: renaming it would leave every one of them unreachable and close
  every folder the user had open. This is the same lesson as the 4a incident at
  one step down — a string that reaches disk cannot be renamed by a rename. The
  type carries a comment saying so. Worth a migration pass if other keys ever
  want tidying; not worth one on its own.
- **The pane header still says "Explorer"**, like the sidebar still says
  "Workspaces". Same reason: rule 3. Both want the same copy pass.
- **The entry view is `FileTreeView`, not `FileTreePanel`.** The phase text
  names `FileTreePanel` as an example of a small entry point; the app's other
  three panes are `AppView`, `EditorView` and `RepositoriesView`, and matching
  them beat matching the parenthetical.
- **`FileTreeModel`'s public surface is three members**: `init(store:)`,
  `selected` and `setRoot(_:)`. Everything else the pane needs — `rows`,
  `toggle`, the renaming and creating methods, `setWatching` — is internal,
  because `FileTreeView` lives in the same module and `AppView` never touched
  them. `FileTreeRow` went internal with them.

## From Phase 5, Editor

- **Highlighting still goes into text storage attributes**, not into
  `NSTextLayoutManager` rendering attributes. `ARCHITECTURE.md` asks for the
  move — it is faster and keeps colour out of the undo stack — but it changes
  how the pane paints, which is behaviour, and this phase was a rename. It is a
  follow-up, and the natural time for it is whenever the editor stops being
  read-only, because the undo-stack half of the argument only starts to matter
  then.
- **The editor's preview cannot show colour.** The real highlighter lives in
  `Services` and a feature may not import it, so the preview runs
  `NoSyntaxHighlighter` and shows the breadcrumb, the gutter and the layout.
  Colour is covered by `SyntaxAttributesTests` and by `EditorModelTests`, which
  is the one feature test target that depends on `Services` for exactly this
  reason. Not a gap, but worth knowing before someone "fixes" the preview.
- **`SyntaxAttributes`' doc comment named the `Syntax` target**, which Phase 2
  dissolved into `Core` and `Services`. Corrected in passing. Phase 6 should
  check for others like it.

## After Phase 5

- **Three features, three naming conventions resolved into one.** Every feature
  is now `Sources/Features/<Name>/` with module `<Name>Feature`, and no feature
  exports more than a model and a view or two. The next feature has a shape to
  copy.
- **Two pieces of user-facing copy still use the old vocabulary**: the sidebar
  header and modal say "workspace" where they mean repository, and the file
  tree's header says "Explorer". Both were left under rule 3 and both want the
  same small copy decision from Kurt.

## From Phase 6 (highlighter boundary)

- **Phase 6 was already true, and that is the finding.** Steps 1, 2 and 4 needed
  no code: the `Syntax` target went in Phase 2, one Swift file imports
  `HerderSyntaxFFI`, and no FFI type leaves it. The survey predicted this at §7.
  What was left was turning a held convention into an enforced one.
- **The new check is the only one that covers the app target.** "Core imports
  Rust" looks at `Sources/Core`, "Feature imports Services or the Rust module"
  at `Sources/Features`; neither sees `Herder/`. Verified by planting a probe
  import in `Core`, in a feature and in `Herder/` and watching each fail, which
  is worth doing to any check that passes the day it is written — a check that
  has never failed has not been tested.
- **One escape hatch retired.** The feature check carried
  `--glob '!**/AppFeature/**'` from when `AppFeature` lived under
  `Sources/Features/`. 2b moved it to `Sources/App/`, so the glob had been
  excluding nothing while still reading as permission. Removed.
- **Three doc comments named the dead `SyntaxTests` target**, in
  `SyntaxTokenKind`, in `TreeSitterHighlighter` and in `ARCHITECTURE.md`. The
  first two now say `TreeSitterHighlighterTests`, which is where the kind-count
  assertion actually lives.
- **Two stale target names left in `ARCHITECTURE.md`**, deliberately not edited:
  line 412 says `SyntaxTests` asserts the kind count (it is
  `TreeSitterHighlighterTests` in `ServicesTests`), and line 369 says
  `StorageTests` keeps the committed V1 fixture (it is `WorkspaceMigrationTests`,
  also in `ServicesTests`, and `Package.swift` and `AppEnvironment`'s
  `fatalError` already say so). Both are wrong names rather than wrong rules, so
  they are Phase 8 step 5's job rather than a quiet edit to the rulebook. An
  agent looking for either test today looks in a target that does not exist.
