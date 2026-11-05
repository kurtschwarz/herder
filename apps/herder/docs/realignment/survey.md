# Phase 0 survey

A factual map of Herder as it stands, against the target in `../ARCHITECTURE.md`.
Read this before starting any realignment task.

Taken at commit `74346ad` (`refactor: rename syntax to syntax-highlighter`), working tree clean.

**Headline:** the codebase is already much closer to the target than `REALIGNMENT.md`
assumes. Phase 1 is a no-op, Phase 2 is a rename rather than a construction, and
Phase 3 is half-done under different names. The real work is Phase 4, and Phase 4
is not a move: most of what it describes does not exist yet. See
[Open questions](#10-open-questions) — several need a decision before Phase 2 starts.

**Path convention here follows the docs:** paths are relative to `apps/herder/`,
except those starting with `packages/`, which are relative to the repo root.

---

## 1. Targets and packages

### Xcode project

`Herder.xcodeproj` is **generated and gitignored**. `project.yml` is the source of
truth; `just project` runs `xcodegen generate`. The docs' layout diagram calls the
project file "thin", which it is, but does not mention that it is generated — any
task that adds a file to the app target must run `just project`.

| Target | Type | Sources | Depends on |
|---|---|---|---|
| `Herder` | macOS app | `Herder/` | HerderKit products `AppFeature`, `Clients`, `Storage` |
| `HerderUITests` | UI test bundle | `UITests/` | `Herder` |

`Herder/` holds `HerderApp.swift` (64 lines), `Info.plist`, `Herder.entitlements`
and `Assets.xcassets`. Nothing else.

**`UITests/` is not in the `ARCHITECTURE.md` layout diagram.** It is XCTest because
Swift Testing has no UI automation. It stays where it is; the diagram needs a line
for it.

### SwiftPM package

`Packages/HerderKit` — **not** `HerderKit/` as the docs' layout diagram says. See
[Q1](#q1-the-docs-paths-do-not-match-the-repo).

`swift-tools-version: 6.2`, `platforms: [.macOS(.v26)]`. Three products are
exported: `AppFeature`, `Clients`, `Storage`.

External dependency: `https://github.com/phosphor-icons/swift` from 2.1.0, product
`PhosphorSwift`. **Not in the `ARCHITECTURE.md` `Package.swift` template.**

| Target | Isolation | Path | Depends on | What's in it |
|---|---|---|---|---|
| `Models` | `core` | default | — | `PathKey`, plus a placeholder `Models.swift` |
| `Clients` | `core` | default | `Models` | 6 client protocols + their `Live` implementations + their value types |
| `ClientsTestSupport` | `core` | default | `Models`, `Clients` | 6 fakes + `FolderKey` |
| `Storage` | `ui` | default | `Models`, `Clients` | SwiftData: 1 `@Model`, schema, container, store, access |
| `Worktrees` | `ui` | default | `Models`, `Clients` | `WorktreeState`, `WorktreeStateStore`, `WorktreeStatus` |
| `HerderSyntaxFFI` | binary | `Vendor/HerderSyntaxFFI.xcframework` | — | the Rust static library + headers |
| `Syntax` | `core` | default | `HerderSyntaxFFI` | `SyntaxHighlighter` protocol, `TreeSitterHighlighter`, `SyntaxToken`, `SyntaxTokenKind`, `SourceText` |
| `DesignSystem` | `ui` | default | `PhosphorSwift` | `Theme`, Views, Modifiers, Shapes |
| `WorkspacesFeature` | `ui` | explicit | `Models`, `Clients`, `DesignSystem`, `Storage`, `PhosphorSwift` | workspace list, worktrees, add + new-session modals |
| `ExplorerFeature` | `ui` | explicit | `Models`, `Clients`, `DesignSystem`, `Worktrees`, `PhosphorSwift` | file tree |
| `EditorFeature` | `ui` | explicit | `Models`, `Clients`, `DesignSystem`, `Syntax`, `Worktrees` | read-only editor, `NSTextView` bridge, gutter |
| `AppFeature` | `ui` | explicit | everything above + the 3 features | `AppModel`, `AppView`, `Sidebar`, `WindowChrome`, preview doubles |

Test targets: `ModelsTests`, `ClientsTests`, `StorageTests`, `SyntaxTests`,
`WorktreesTests`, and `<Name>FeatureTests` for each of the four features under
`Tests/Features/`.

11,068 lines of Swift across 79 files, Sources and Tests together.

### Repo root

- Root `justfile` forwards recipes to `apps/<name>/justfile` or
  `packages/<name>/justfile` by the same recipe name. It is generic; it names no app.
- Root `README.md` (13 KB) carries the rationale for the **current** structure and
  will go stale as this plan runs. See [Q7](#q7-three-documents-will-contradict-architecturemd).
- No CI configuration anywhere in the repo.
- No `services/` directory, despite the root `justfile` globbing for one.

---

## 2. Commands

All from `apps/herder/`, or from the root as `just <recipe> apps/herder`.

```sh
just bootstrap     # syntax + project. Needed once in a fresh clone.
just syntax        # cargo build (both arches) -> lipo -> xcframework -> rsync into Vendor/
just project       # xcodegen generate
just build         # project + syntax, then xcodebuild -configuration Debug -quiet build
just test          # syntax, then xcodebuild test -scheme HerderKit-Package  (34 tests)
just dev           # build, then run with output in this terminal
just uitest        # xcodebuild test on the Herder scheme (slow, launches the app)
just clean
```

And in `packages/syntax-highlighter/`:

```sh
just build         # the XCFramework
just test          # cargo test + cargo clippy --all-targets -- -D warnings
just dump <file>   # print the tokens for a file
```

Three corrections to the "Definition of done" in `REALIGNMENT.md`:

1. **`swift test` does not work here.** Tests go through `xcodebuild test -scheme
   HerderKit-Package`, because PhosphorSwift ships its icons as an asset catalog
   without declaring it a resource, which only Xcode's build system bundles. Use
   `just test`.
2. **The build command needs the generated project.** `xcodebuild -scheme Herder
   -destination 'platform=macOS' build` fails in a clean clone until `just project`
   has run, and `platform=macOS` alone makes xcodebuild warn that it picked an arch.
   Use `just build`.
3. **The Rust command is `just test` in the crate**, which is `cargo test` *and*
   `cargo clippy -D warnings`. Clippy is part of green.

### Verified baseline

Run on 2026-11-05 before any change:

| Check | Result |
|---|---|
| `just build` | succeeds |
| `just test` | 34 tests in 3 suites, **TEST SUCCEEDED** |
| Swift compiler warnings | **zero** |
| `cargo test` | passes |
| `cargo clippy --all-targets -- -D warnings` | passes |

(The only "warning" lines in build output are xcodebuild's multiple-destination
note and `appintentsmetadataprocessor` saying there is no AppIntents dependency.
Neither is ours.)

---

## 3. Concurrency status

**Phase 1 is already done.** No throwaway branch was needed to find this out.

- `Package.swift` is `swift-tools-version: 6.2`, so every HerderKit target is in
  Swift 6 language mode.
- `project.yml` sets `SWIFT_VERSION: "6.0"`, `SWIFT_STRICT_CONCURRENCY: complete`,
  `SWIFT_UPCOMING_FEATURE_NONISOLATED_NONSENDING_BY_DEFAULT: YES`,
  `SWIFT_APPROACHABLE_CONCURRENCY: YES`, and
  `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` for the app target.
- Per-target default isolation is already in place, with the same two settings the
  target architecture asks for:
  - `ui` = `.defaultIsolation(MainActor.self)` + `NonisolatedNonsendingByDefault`
  - `core` = `.defaultIsolation(nil)` + `NonisolatedNonsendingByDefault`
- **Zero concurrency warnings** across build and tests.

This goes further than `ARCHITECTURE.md` asks: the target doc does not mention
`NonisolatedNonsendingByDefault`, which is enabled everywhere here and is what
makes `@concurrent` meaningful on `TreeSitterHighlighter.tokens`.

### Escape hatches (3, all justified in place)

| Where | What | Why |
|---|---|---|
| `Clients/FileWatcher/LiveFileWatcherClient.swift:45` | `WatchSession: @unchecked Sendable` | FSEvents C callback; every mutable property is touched only on its own `DispatchQueue`. Documented at line 43. |
| `Tests/ClientsTests/FileWatcherClientTests.swift:22` | `Batches: @unchecked Sendable` | test accumulator |
| `Tests/Features/EditorFeatureTests/EditorModelTests.swift:16` | `SlowSyntaxHighlighter: @unchecked Sendable` | single-threaded test double, documented at line 14 |

No `nonisolated(unsafe)`, no `@preconcurrency`.

### `DispatchQueue` (2)

| Where | What |
|---|---|
| `Clients/FileWatcher/LiveFileWatcherClient.swift:49,97` | FSEvents requires a dispatch queue. Not replaceable. |
| `Features/EditorFeature/Platform/LineNumberRuler.swift:58` | `DispatchQueue.main.async` to defer `needsDisplay` out of a layout pass. AppKit. |

Both are at an AppKit/C boundary. `ARCHITECTURE.md` says "no new `DispatchQueue`
usage"; neither of these is new, and neither has an `async`/`await` equivalent.
They want a `// CONCURRENCY:` comment in Phase 8 rather than removal.

---

## 4. SwiftData inventory

Smaller than `REALIGNMENT.md` assumes: **one model, one `@Query`, 5 files**.

### The one `@Model`

`Storage/WorkspaceSchemaV1.swift` — `WorkspaceSchemaV1.Workspace`, aliased to
`Workspace`. A folder the user has adopted.

| Field | Type | Recreatable from disk or git? |
|---|---|---|
| `id` | `UUID`, `@Attribute(.unique)` | **No.** Stable identity; order, selection and sessions key off it. |
| `name` | `String` | **No.** Defaults to the folder name, then is the user's to change, and deliberately does not follow a folder rename. |
| `path` | `String` | Yes — a cache of where the bookmark last resolved. |
| `bookmark` | `Data` | **No.** Security-scoped bookmark: the standing permission to reopen the folder. Cannot be regenerated without the user picking the folder again. |
| `order` | `Int` | **No.** Sidebar order, the user's arrangement. |
| `addedAt` | `Date` | **No.** |
| `isAvailable` | `Bool`, `@Transient` | Yes — a fact about right now. |

**This is a "stop and ask" case under rule 3 of `REALIGNMENT.md`.** `name`, `order`
and `bookmark` cannot be recreated: dropping the store makes the user re-pick every
folder and re-name and re-order every row. See [Q6](#q6-the-workspace-model-holds-data-that-cannot-be-recreated).

No relationships. No other `@Model` anywhere.

### Everything that touches SwiftData

| File | Use |
|---|---|
| `Herder/HerderApp.swift:13,45,57-63` | builds the container, `fatalError` if it cannot; `.modelContainer(container)` on the `WindowGroup` |
| `Storage/WorkspaceContainer.swift` | the only place that knows the schema, migration plan and store URL. `live()` and `inMemory()`. CloudKit off on purpose: bookmarks are machine-specific. |
| `Storage/WorkspaceStore.swift` | the only writer. Holds a `ModelContext`. `validate`/`add`/`open`/`relocate`/`rename`/`delete`/`reorder`/`workspaces()` |
| `Storage/WorkspaceSchemaV1.swift` | the model + `WorkspaceMigrationPlan` (no stages yet) |
| `Features/WorkspacesFeature/WorkspacesView.swift:11` | **the one `@Query`**, sorted by `order` then `addedAt` |
| `Features/AppFeature/AppModel.swift:6,47` | takes `context: ModelContext` in `init` and passes it to `WorkspaceStore` |
| `Features/AppFeature/AppView.swift:68`, `Components/Sidebar.swift:38` | `.modelContainer(AppModel.previewContainer)` in `#Preview` |
| `Tests/StorageTests`, `Tests/Features/WorkspacesFeatureTests`, `Tests/Features/AppFeatureTests` | `ModelContext(container)` over `WorkspaceContainer.inMemory()` |

`~/Library/Application Support/Herder/Workspaces.store`.

Note the design `AppModel:38` relies on: the store writes through the app's
`mainContext`, the same context `@Query` reads, so a change shows in the sidebar
with no round trip. Replacing `@Query` with reads from a store (Phase 4d) has to
replace that mechanism, not just the call site.

---

## 5. Global and shared state

**There are no singletons.** `rg 'static (let|var) shared'` finds nothing. No
`@EnvironmentObject`, no `@StateObject`, no `@AppStorage`, no `@SceneStorage`.

Dependency injection is already what `ARCHITECTURE.md` asks for: `HerderApp.init`
constructs the six live clients and the container, hands them to `AppModel`, and
`AppModel` builds the feature models. Everything else takes what it needs through
`init`. **The singleton check in `check-boundaries.sh` passes today.**

Two pieces of de facto global state:

1. **`UserDefaults.standard`**, reached directly in
   `Features/WorkspacesFeature/WorkspacesModel.swift:27,77` (injectable, defaulted)
   for three keys: `collapsedWorkspaces`, `selectedWorktreePath`,
   `selectedWorktreeWorkspace`. This is persisted UI state not behind a client, and
   is exactly what `PersistedWorkspaceUIState` + `StateStore` is for.
2. **The Rust crate's process-global compiled-query cache**, warmed by
   `Task.detached { await TreeSitterHighlighter.warmUp() }` in `AppModel.start()`.
   Stateless from Swift's side.

### `NotificationCenter` (7 uses, none carrying app state)

All AppKit window and application lifecycle:

| Where | Notification |
|---|---|
| `Herder/HerderApp.swift:37` | `NSApplication.willTerminateNotification` → `model.stop()` |
| `Features/WorkspacesFeature/WorkspacesView.swift:42` | `NSWindow.didBecomeKeyNotification` |
| `Features/ExplorerFeature/ExplorerView.swift:78,81` | `didBecomeKey` / `didResignKey` → `setDraining` |
| `Features/EditorFeature/Platform/LineNumberRuler.swift:31` | text/scroll change observer |
| `Features/AppFeature/Platform/WindowChrome.swift:21,60` | window observer |

Note `willTerminateNotification` is the only place security-scoped access is handed
back. Any change to app lifecycle must keep it.

---

## 6. External dependencies — the Phase 3 service list

**Phase 3 is substantially already done, under the name `Clients`.** Every external
dependency is behind a `Sendable` protocol with a `Live` implementation and a fake.

| Protocol | File | Live | Fake | Touches |
|---|---|---|---|---|
| `FileClient` | `Clients/File/FileClient.swift` | `LiveFileClient` | `InMemoryFileClient` | disk: `children(of:)`, `create`, `move`, reads |
| `GitClient` | `Clients/Git/GitClient.swift` | `LiveGitClient` (511 lines) | `StubGitClient` | `Process()` running `git`, plus direct `FileManager` reads of `.git` internals |
| `FileWatcherClient` | `Clients/FileWatcher/FileWatcherClient.swift` | `LiveFileWatcherClient` | `StubFileWatcherClient` | FSEvents (`import CoreServices`) |
| `BookmarkClient` | `Clients/Bookmark/BookmarkClient.swift` | `LiveBookmarkClient` | `InMemoryBookmarkClient` | security-scoped bookmarks |
| `FolderPickerClient` | `Clients/FolderPicker/FolderPickerClient.swift` | `LiveFolderPickerClient` | `StubFolderPickerClient` | `NSOpenPanel` |
| `ClockClient` | `Clients/Clock/ClockClient.swift` | `LiveClockClient` | `VirtualClockClient` | `ContinuousClock` |

Plus:

| Protocol | File | Real | Fake | Touches |
|---|---|---|---|---|
| `SyntaxHighlighter` | `Syntax/SyntaxHighlighter.swift` | `TreeSitterHighlighter` | `NoSyntaxHighlighter` (ships in `Syntax`, not in TestSupport) | the Rust crate over a C ABI |

**No network anywhere.** No `URLSession`.

**No process or PTY service beyond git.** `Process()` appears only in
`LiveGitClient` and in two test helpers. Nothing spawns a shell, a PTY or an agent.

### Gaps against the target shape

1. **Protocol and implementation are co-located**, both in the `Clients` target.
   `ARCHITECTURE.md` wants the protocol in `Core/Services/` and the implementation
   in `Services/<Area>/`. Features import `Clients` today (38 imports, the second
   most of any module) and so can see the `Live` types; the dependency rules say
   they must see only the protocol.
2. **The value types live with the clients, not in `Models`.** `DirectoryEntry`,
   `FileClientError`, `GitStatus`, `GitChange`, `GitWorktreeStatus`, `GitWorktree`,
   `GitRepositoryKind`, `GitClientError`, `FileWatcherPosition`, `FileChangeBatch`,
   `ResolvedBookmark`, `BookmarkClientError` are all declared in `Clients/`.
   `Models` holds only `PathKey` and a placeholder. Moving these to `Core/Models/`
   is most of Phase 2 step 3.
3. **`NoSyntaxHighlighter` ships in the product**, not in `ClientsTestSupport`. The
   doc comment argues for this deliberately ("turns highlighting off without a flag
   to read anywhere"). `ARCHITECTURE.md` wants every fake in `TestSupport`.
4. **`ClientsTestSupport` is named for `Clients`**, and the target doc calls it
   `TestSupport` with fakes under `TestSupport/Fakes/`.
5. **No `StateStore`.** Persistence is SwiftData reached directly, plus
   `UserDefaults` in `WorkspacesModel`.
6. **No `Settings` service, no keybindings, no theme service.** `Theme` is static
   constants in `DesignSystem`.

---

## 7. Syntax highlighter

### Layout of `packages/syntax-highlighter`

```
packages/syntax-highlighter/
├── Cargo.toml              # crate herder-syntax, edition 2024, crate-type ["staticlib", "rlib"]
├── Cargo.lock
├── rust-toolchain.toml
├── .cargo/config.toml
├── justfile                # bootstrap / build / test / dump / clean
├── AGENTS.md
├── include/
│   ├── herder_syntax.h     # hand-written C header
│   └── module.modulemap    # hand-written, module HerderSyntaxFFI
├── src/{lib,highlight,kind,language}.rs
└── examples/{bench,dump}.rs
```

16 tree-sitter grammars. `panic = "abort"`, because a panic must not unwind across
the C ABI.

### How Swift sees it

- **Bindings are hand-written, not generated.** No UniFFI, no cbindgen. A C header
  and a modulemap in `include/`, declaring module `HerderSyntaxFFI`. So
  `ARCHITECTURE.md`'s "Generated binding code is never hand-edited" does not apply
  as written — there is no generated code. The header is the API and it is edited
  by hand, in step with `src/lib.rs`.
- **It does not ship a `Package.swift`.** It builds an **XCFramework**, which is the
  documented fallback: `.binaryTarget` + a thin Swift target. So the `RustBridge`
  role is filled by the existing **`Syntax`** target, and `RUST_MODULE` in
  `check-boundaries.sh` is **`HerderSyntaxFFI`**.
- **Build output:** `packages/syntax-highlighter/target/HerderSyntaxFFI.xcframework`,
  `rsync`'d by `just syntax` into `Packages/HerderKit/Vendor/`. Both are gitignored
  build artifacts. A fresh clone must run `just bootstrap` before SwiftPM will
  resolve the package at all.
- **The `.binaryTarget` path is relative to the package** (`Vendor/...`), not to the
  crate. The crate does not know who consumes it. This is cleaner than the template's
  `.binaryTarget(path: "../../../packages/syntax-highlighter/...")` and should be
  kept — see [Q2](#q2-how-should-herderkit-consume-the-xcframework).

### Public C API (`include/herder_syntax.h`)

`hdr_language_for`, `hdr_highlight`, `hdr_tokens_free`, `hdr_warm`,
`hdr_kind_count`, `hdr_language_count`, and the types `HdrToken`,
`HDR_LANGUAGE_NONE`.

### Swift files that import `HerderSyntaxFFI`

**Exactly one: `Syntax/TreeSitterHighlighter.swift`.** The boundary
`ARCHITECTURE.md` rule 7 asks for already holds.

### Offsets — already settled, and not where the doc expects

`ARCHITECTURE.md` says conversion happens in the service wrapping the FFI.
**It already happens in Rust.** `SyntaxToken`'s doc comment: "`range` is in UTF-16
code units … Tree-sitter counts bytes; the crate converts before handing them over,
because a conversion a caller has to remember is one a caller will forget."

So `HdrToken.start`/`end` are **already UTF-16**, and there is no conversion to put
anywhere. Phase 6 step 3 is already satisfied; recording it here is the whole of
that step.

### What consumes `Syntax`

`EditorFeature` (`EditorModel`, `SyntaxAttributes`) and `AppFeature` (`AppModel`,
for `warmUp`). Both see Swift types only — `SyntaxToken`, `SyntaxTokenKind`,
`SourceText`, the `SyntaxHighlighter` protocol — never FFI types.

Under the target rules those Swift types belong in `Core/Models/` and the protocol
in `Core/Services/`, with `TreeSitterHighlighter` in `Services/Highlighting/`. That
is a three-way split of a 5-file module whose boundary is already correct, and
`SyntaxTokenKind`'s raw values are asserted against the crate by `SyntaxTests`.

---

## 8. Feature inventory

### Mapping: current → target home

| Current path | Lines | Target home | Confidence |
|---|---|---|---|
| `Herder/HerderApp.swift` | 64 | `App` | certain |
| `Herder/{Info.plist,Herder.entitlements,Assets.xcassets}` | — | `App/Resources` | certain |
| `UITests/` | — | stays (not in the target diagram) | — |
| `Sources/Models/PathKey.swift` | 113 | `Core/Models/` | certain |
| `Sources/Models/Models.swift` | 12 | delete (placeholder) | certain |
| `Sources/Clients/*/....Client.swift` (protocols) | 277 | `Core/Services/` | certain |
| `Sources/Clients/*/Live*.swift` | 856 | `Services/{FileSystem,Git,Process,...}/` | certain |
| `Sources/Clients/Git/{GitStatus,GitRefName,GitWorktreeLocation}.swift` | 139 | `Core/Models/` (values) + `Services/Git/` (parsers) | **needs splitting** |
| `Sources/Clients/File/FileClient.swift` → `DirectoryEntry`, `FileClientError` | — | `Core/Models/` | certain |
| `Sources/ClientsTestSupport/` | 573 | `TestSupport/Fakes/` | certain |
| `Sources/Storage/WorkspaceSchemaV1.swift` | 72 | `Services/Persistence/` | certain |
| `Sources/Storage/WorkspaceContainer.swift` | 40 | `Services/Persistence/` | certain |
| `Sources/Storage/WorkspaceStore.swift` | 192 | **unclear** — see [Q5](#q5-the-target-architecture-has-no-home-for-the-workspace-list) |
| `Sources/Storage/WorkspaceAccess.swift` | 41 | `Services/FileSystem/` (sandbox access) | likely |
| `Sources/Storage/WorkspaceStoreError.swift` | — | `Core/Models/` | certain |
| `Sources/Worktrees/WorktreeState.swift` | 414 | `Core/Workspace/` → becomes `Workspace` | **see [Q4](#q4-workspace-already-means-something-else)** |
| `Sources/Worktrees/WorktreeStateStore.swift` | 104 | `Core/Workspace/` → becomes `WorkspaceRegistry` | **see [Q4](#q4-workspace-already-means-something-else)** |
| `Sources/Worktrees/WorktreeStatus.swift` | 120 | `Core/Models/` | certain |
| `Sources/Syntax/SyntaxHighlighter.swift` | 34 | `Core/Services/` | certain |
| `Sources/Syntax/{SyntaxToken,SyntaxTokenKind,SourceText}.swift` | 87 | `Core/Models/` | certain |
| `Sources/Syntax/TreeSitterHighlighter.swift` | 82 | `Services/Highlighting/` | certain |
| `Sources/DesignSystem/` | 582 | `DesignSystem/` | certain |
| `Sources/Features/EditorFeature/` | 562 | `Features/Editor/` (module `EditorFeature`) | certain |
| `Sources/Features/ExplorerFeature/` | 796 | `Features/FileTree/` (module `FileTreeFeature`) | **rename — see [Q3](#q3-explorerfeature-is-the-target-doc-s-filetreefeature)** |
| `Sources/Features/WorkspacesFeature/` | 1,355 | **no slot in the target list** — see [Q5](#q5-the-target-architecture-has-no-home-for-the-workspace-list) |
| `Sources/Features/AppFeature/AppModel.swift` | 89 | `App/AppEnvironment.swift` + `App/` | **see [Q8](#q8-does-appfeature-dissolve-into-the-app-target)** |
| `Sources/Features/AppFeature/AppView.swift` | 70 | `App/` | **see [Q8](#q8-does-appfeature-dissolve-into-the-app-target)** |
| `Sources/Features/AppFeature/Components/Sidebar.swift` | 44 | `App/` | see Q8 |
| `Sources/Features/AppFeature/Platform/WindowChrome.swift` | 154 | `App/` or `DesignSystem` | see Q8 |
| `Sources/Features/AppFeature/Previews/PreviewClients.swift` | 101 | `TestSupport/` | certain |

### Target features that do not exist yet

`AgentSessionsFeature`, `TerminalFeature`, `TerminalUI`, `SearchFeature`,
`CommandPaletteFeature`, `SettingsFeature` — **none of these exist.** No PTY
service, no agent runner, no search, no palette, no settings UI.

`NewSessionModel` creates a git worktree and can *choose* an existing one, but its
own doc comment says "opening a session in an existing worktree waits for a session
runtime, so that choice can be made but not submitted." There is no session runtime.

### Target state types that do not exist yet

`DocumentStore`, `Document`, tabs, dirty state, `AgentSessionStore`,
`AgentSessionRef`, `WorkspaceID`, `WorkspaceRegistry`, `WorkspaceUIState`,
`PersistedWorkspaceUIState`, `AppSnapshot`, `WorkspaceSnapshot`,
`WorkspaceServicesFactory`, `WindowModel`, `StateStore`.

The editor is **one read-only file at a time**. `EditorModel` has no tabs, no dirty
flag, no save. See [Q9](#q9-phase-4-is-not-a-move).

---

## 9. Cross-feature coupling

**No feature imports another feature.** `import WorkspacesFeature`,
`import ExplorerFeature` and `import EditorFeature` appear only in `AppFeature` and
in the corresponding test targets. The rule the target doc states is already held.

Coordination goes through `AppView`'s `.task(id:)` modifiers, which is the current
answer to what the target doc answers with `Workspace`:

| At | Crosses |
|---|---|
| `AppView.swift:35` | `.task(id: model.workspaceList.selectedWorktree)` → closes the editor, sets the explorer's root. Comment: "The sidebar owns the selection and the explorer must not import it, so the plain URL crosses here." |
| `AppView.swift:42` | `.task(id: model.explorer.selected)` → opens the file in the editor |
| `AppView.swift:28,31` | `model.workspaceList.selectedWorkspaceName` passed into both the editor and the explorer |
| `AppView.swift:46` | `.disabled(model.workspaceList.isModalPresented)` gates the whole window on the sidebar's modal |

Shared below the features:

- `Worktrees` (`WorktreeStateStore`) is read by `ExplorerFeature` and
  `EditorFeature`, which is the current stand-in for `Workspace`. This is already
  the shape the target doc wants, one level down.
- `Storage` is imported by `WorkspacesFeature` **and** `AppFeature`, so SwiftData
  reaches into a feature today (`@Query` in `WorkspacesView`, `import SwiftData` in
  `Sidebar`). Violates target rule 6.
- `Clients` is imported by all four features. After the Core/Services split they
  must import `Core` only.
- `PhosphorSwift` is imported directly by `WorkspacesFeature` and `ExplorerFeature`,
  not only by `DesignSystem`. The template's `feature()` helper has no slot for it
  without `extraDeps`.

One coupling worth keeping in mind for Phase 5: `GitMark` lives in `Worktrees` and
is used by `ExplorerRow` in `ExplorerFeature`; the commit before last was
"refactor(herder): fold ExplorerMark into GitMark", i.e. this was deliberately
pushed down out of the feature.

---

## 10. Open questions

**All resolved.** Kurt answered these on 2026-11-05 and the answers are recorded as
D1–D10 in the "Decisions" section of `../REALIGNMENT.md`, which is the authoritative
version. `ARCHITECTURE.md` has been amended to match. This section is kept as the
reasoning behind each decision, not as a live list.

| Question | Resolution |
|---|---|
| Q1 paths | D1 — keep `Packages/HerderKit/` and `Herder/`; amend the docs |
| Q2 XCFramework | D2 — keep the vendored copy |
| Q3 `ExplorerFeature` | D3 — rename to `FileTreeFeature`, types included |
| Q4 `Workspace` | D4 — option (a): `WorktreeState` → `Workspace`, `@Model Workspace` → `Repository` |
| Q5 workspace list | D5 — `RepositoriesFeature`, app-scoped |
| Q6 unrecreatable data | D6 — migrate, never drop; bookmark storage decided before Phase 7 |
| Q7 contradicting docs | D7 — `AGENTS.md` becomes a pointer; the four orphan rules move into `ARCHITECTURE.md` |
| Q8 `AppFeature` | D8 — option (b): composition root is the module, at `Sources/App/` |
| Q9 Phase 4 | D9 — cut to what exists; smoke test rewritten |
| Q10 smaller items | D10 — all folded into `ARCHITECTURE.md` |

Ordered below by what blocked what.

### Q1. The docs' paths do not match the repo

`ARCHITECTURE.md`'s layout diagram puts the package at `apps/herder/HerderKit/` and
the app sources at `apps/herder/App/`. They are actually at
`apps/herder/Packages/HerderKit/` and `apps/herder/Herder/`.

`ARCHITECTURE.md:54` already allows the app folder to differ ("real folder name from
the survey"), and `check-boundaries.sh` has `APP_DIR` for it — so `Herder/` is fine,
set `APP_DIR=Herder`. But `HerderKit`'s path is hard-coded in the diagram, in
`SRC="HerderKit/Sources"` in the boundary script, and in the `.package(path:)` in the
template.

**Recommendation:** keep `Packages/HerderKit/` (it is what `project.yml`,
`justfile` and `AGENTS.md` all reference, and `Packages/` leaves room for a second
local package) and amend the docs. Needs your call, because it edits
`ARCHITECTURE.md`, which rule 30 says not to do quietly.

### Q2. How should HerderKit consume the XCFramework?

The crate ships no `Package.swift`, so the documented fallback applies:
`.binaryTarget` + a thin wrapper. That is **exactly what exists** — a
`.binaryTarget` on `Vendor/HerderSyntaxFFI.xcframework` (rsync'd in by
`just syntax`) plus the `Syntax` target.

The template instead suggests `.binaryTarget(path:
"../../../packages/syntax-highlighter/<path>")`, pointing out of the app directory
into the crate's `target/`.

**Recommendation:** keep the vendored copy. Reaching into another package's
`target/` from a `Package.swift` path couples SwiftPM resolution to Cargo's output
directory, and `just syntax` already guarantees freshness. Confirm.

### Q3. `ExplorerFeature` is the target doc's `FileTreeFeature`

The target names the module `FileTreeFeature` at `Sources/Features/FileTree/`.
Herder calls it `ExplorerFeature`, and "explorer" is used throughout its types
(`ExplorerModel`, `ExplorerRow`, `ExplorerRowView`, `ExplorerView`) and tests.

**Recommendation:** rename to `FileTree`/`FileTreeFeature` as the docs say, in the
Phase 5 FileTree task, types included — one vocabulary beats two. Confirm you want
the rename and not an amendment to the docs.

### Q4. `Workspace` already means something else

This is the biggest semantic gap, and it is not a rename.

| Term | Means here, today | Means in `ARCHITECTURE.md` |
|---|---|---|
| `Workspace` | a `@Model`: a **repository folder the user adopted**, with a bookmark, a name and a sidebar position | "**one folder or git worktree**" — live state, `DocumentStore` + `AgentSessionStore` + git state + UI state |
| `WorktreeState` | live state of **one checkout**: listings, git status, watcher | ≈ the target's `Workspace` |
| `WorktreeStateStore` | the registry of live `WorktreeState`s (currently holds exactly one) | ≈ the target's `WorkspaceRegistry` |
| `GitWorktree` | a checkout as **git reports it** | no equivalent |

Herder's model is **two levels**: an adopted repository has N git worktrees, and one
of those is selected and has live state. The target architecture's hierarchy is
`WorkspaceRegistry → Workspace` — **one level**, with no term for the adopted
repository.

So "`Workspace` is the single source of truth for one checkout" collides with the
existing `Workspace`, which is a source of truth for a *repository*. Renaming
`WorktreeState` → `Workspace` requires renaming the current `Workspace` to something
else at the same time, and the docs do not say to what.

**Options:**
- **(a)** Keep two levels and add a term: the `@Model` becomes `Repository` (or
  `Project`), and `WorktreeState` becomes `Workspace`. Needs an amendment to
  `ARCHITECTURE.md`'s state hierarchy to show the repository level.
- **(b)** Flatten: a `Workspace` *is* one worktree, and the adopted repository
  becomes a plain grouping in the sidebar's snapshot rather than a first-class type.
  Closest to the docs, biggest change to the app's shape.
- **(c)** Keep `WorktreeState`/`WorktreeStateStore` and substitute those names for
  `Workspace`/`WorkspaceRegistry` throughout the docs.

**Recommendation: (a).** It matches what the app does, costs one rename, and the
two-level model is a real feature (the sidebar lists repos, each expanding to its
worktrees) rather than an accident. But this is yours to decide, and it changes
`ARCHITECTURE.md`.

### Q5. The target architecture has no home for the workspace list

`WorkspacesFeature` is the largest feature (1,355 lines: the sidebar list, worktree
rows, the add-workspace modal, the new-session modal, relative ages) and
`WorkspaceStore` (192 lines) is the whole of its domain logic.

The target's feature list — Editor, FileTree, AgentSessions, Terminal, Search,
CommandPalette, Settings — has no slot for it, and the `Package.swift` template does
not include it.

Following Q4(a): it becomes `Features/Repositories/` (module
`RepositoriesFeature`), with `WorkspaceStore`'s logic behind a protocol in
`Core/Services/` and an implementation in `Services/Persistence/`.

**Needs your call on the name and on adding it to the docs' feature list.**

### Q6. The `Workspace` model holds data that cannot be recreated

Flagged under rule 3 of `REALIGNMENT.md` and under the Phase 4d "stop and ask".

`name`, `order`, `bookmark` and `addedAt` are not recoverable from disk or git. In
particular the **security-scoped bookmark** cannot be regenerated without the user
re-picking the folder in an `NSOpenPanel`.

Consequences:

1. **Phase 4d** says "delete the old `@Model` types once nothing reads them". Doing
   that without a migration makes every user re-adopt every folder.
2. **Phase 7** says "No data migration is needed while Herder is unshipped … The
   first launch after the swap starts fresh." Even unshipped, that is your own
   workspace list on your own machine, lost on the swap.
3. **`FileStateStore` writing JSON would put the bookmark in a plain file.**
   `ARCHITECTURE.md:271` says "Secrets go in the Keychain, never a file." A
   security-scoped bookmark is not a secret exactly, but it is a capability. Needs a
   decision: JSON (base64 `Data`), Keychain, or keep SwiftData for just this.

**Recommendation:** write a one-shot `SwiftDataStateStore` → snapshot migration in
Phase 4d rather than dropping the table, and decide bookmark storage before Phase 7.
Not blocking Phase 2.

### Q7. Three documents will contradict `ARCHITECTURE.md`

- **`apps/herder/AGENTS.md`** (125 lines) documents the current structure in
  detail — `Clients/`, `Storage/`, `Worktrees/`, `Syntax/`, the "where a new file
  goes" table, and rules like "features depend on `Models`, `Clients`, `Storage`,
  `Worktrees` and `DesignSystem`". From Phase 2 on it is wrong, and it is the file
  an agent reads first.
- **`README.md` at the repo root** (13 KB) carries the rationale for the current
  structure. Rule 11 says not to touch repo-root config; a README is not config, but
  it is outside `apps/herder/`.
- **`packages/syntax-highlighter/AGENTS.md`** — needs checking for references to the
  Swift side's layout. Rule 20 says leave the package alone.

**Recommendation:** reduce `apps/herder/AGENTS.md` to a short pointer at
`docs/ARCHITECTURE.md` plus the handful of rules that are genuinely Herder-specific
and not in it (`PathKey` over raw `URL`; tokens only applied to the string they were
found in; a reload that finds the same text changes nothing; token kinds and colours
kept apart). Those four are hard-won and are **not** in `ARCHITECTURE.md` — they
should be added to it rather than lost. Update `AGENTS.md` in the same PR as each
phase that invalidates part of it. Leave the root README until Phase 8, then ask.

### Q8. Does `AppFeature` dissolve into the app target?

`ARCHITECTURE.md:15` makes the App target the composition root, and Phase 5's
done-when is "the app target contains only composition, windows, and commands" —
which is exactly `AppModel` + `AppView` + `Sidebar` + the menu commands.

But `apps/herder/AGENTS.md` and `project.yml`'s comments both insist the app target
stay near-empty, with composition in `AppFeature`, for a stated reason: the Xcode
project is generated, so **every file added under `Herder/` needs `just project`**,
while files under `HerderKit` are picked up by SwiftPM automatically. Composition
code changes often.

**Options:**
- **(a)** Move `AppModel`/`AppView` into `Herder/` as `AppEnvironment.swift` /
  `WorkspaceView.swift`, per the docs. Accept the `just project` step.
- **(b)** Keep an `AppFeature` target as the composition module, with `Herder/`
  holding only `@main` + resources, and read "App target" in the docs as "the
  composition root, whether that is the Xcode target or the one module only it
  depends on."

**Recommendation: (b)**, amending `ARCHITECTURE.md` to say so. `just project` is
real friction, `xcodegen`'s `generateEmptyDirectories` and globbed sources make the
app target's file list a build input, and nothing in the dependency rules actually
needs the composition root to be the Xcode target — only that exactly one place
knows the concrete types. Your call.

### Q9. Phase 4 is not a move

`REALIGNMENT.md` rule 3 is "move first, change later", and Phase 4 is written as
moving state into new holders. But most of Phase 4's subject does not exist:

| Phase 4 step | Reality |
|---|---|
| 4c "open documents and tabs → `DocumentStore`" | **no tabs, no documents.** The editor is one read-only file. There is no dirty state and no save. |
| 4c "agent sessions → `AgentSessionStore`" | **no agent sessions.** No session runtime at all. |
| 4c "git branch and status → `Workspace`" | exists, in `WorktreeState.status`. A real move. |
| 4c "feature UI state that must survive a switch" | exists: `ExplorerModel.expanded`, `WorkspacesModel.collapsed`/`selectedWorktree`. A real move. |
| 4f "confirm agent sessions and documents in background workspaces survive a switch" | nothing to survive. `WorktreeStateStore.select` deliberately **stops** every other worktree today, keeping only the watcher position. |
| Smoke test step 2 "Edit and save" | **not possible.** Read-only. |
| Smoke test step 3 "Start an agent session. It runs and responds." | **not possible.** |
| Smoke test step 4 "the agent in the first worktree keeps running, tabs and scroll positions restore" | **not possible.** |

So Phase 4 splits into two different kinds of work: moving the state that exists
(git state, UI state, restoration) and **building features that do not** (documents,
tabs, dirty state, saving, agent sessions, multi-workspace liveness). The second
kind is new product work, not realignment, and `WorktreeStateStore`'s doc comment
says widening it to several live worktrees is meant to be "a deliberate step and not
a side effect".

**Recommendation:** cut Phase 4 down to what can be moved — `WorkspaceRegistry`,
`Workspace`, UI state, snapshots, `StateStore`, restoration, and
`WindowModel.activeWorkspaceID` — and leave `DocumentStore`/`AgentSessionStore` as
empty-but-present seams, or out entirely until the features exist. Then rewrite the
smoke test to what the app can actually do. Needs your call; it rewrites a phase.

### Q10. Smaller items, not blocking

1. **`just test`, not `swift test`.** The definition of done needs correcting (§2).
2. **Clippy is part of green**, not just `cargo test` (§2).
3. **`PhosphorSwift`** is missing from the `Package.swift` template and is imported
   directly by two features, which the `feature()` helper does not allow.
4. **`UITests/`** is missing from the layout diagram.
5. **`Herder.xcodeproj` is generated**; the diagram calls it thin but not generated.
6. **`NonisolatedNonsendingByDefault`** is enabled everywhere and is not mentioned
   in `ARCHITECTURE.md`'s concurrency section. It should be, since `@concurrent`
   depends on it.
7. **Offsets are already UTF-16 from Rust** (§7). `ARCHITECTURE.md:314` describes a
   conversion in the service that does not and should not exist.
8. **Bindings are hand-written, not generated** (§7). `ARCHITECTURE.md:309`
   ("generated binding code is never hand-edited") needs rewording.
9. **`Theme` is static constants**, and the scoping table lists "Settings,
   keybindings, theme" as an app-scoped service. Nothing to move yet.
10. **No CI** anywhere, so Phase 8 step 3 has nothing to add a job to. A pre-commit
    hook is the only option as things stand.
11. **`default.profraw`** files are sitting untracked at the repo root and in
    `apps/herder/`. Coverage droppings; worth a `.gitignore` line.
12. **`.DS_Store` is tracked-adjacent** in several directories. Same.
