# Herder Architecture

This is the target architecture for Herder and the rulebook for anyone (human or agent) changing the code. If the code and this document disagree, assume the code is wrong. If you think the document is wrong, stop and ask Kurt rather than quietly diverging.

## Stack

- Swift 6 language mode, `swift-tools-version: 6.2`, macOS 26 and later
- SwiftUI for the app shell and panels; AppKit (`NSTextView` with TextKit 2) for the editor surface
- Rust for performance-sensitive work, starting with the syntax highlighter in `packages/syntax-highlighter`. That package stays where it is and keeps its own build and binding setup.
- Zig, only to build libghostty-vt (the terminal emulation under the terminal panel) from a pinned Ghostty commit: `packages/ghostty-vt`. Zig 0.17.x, `brew install zig`. We write no Zig.
- Distributed with Developer ID signing and notarization. No App Sandbox, because Herder spawns processes and opens arbitrary folders.

## Layers

```
Herder target         @main, Info.plist, entitlements, assets. Nothing else.
  │
  ▼
AppFeature            composition root: windows, menus, builds real services
  │
  ├──► Features        UI + feature state (Editor, FileTree, AgentSessions, ...)
  │       │
  │       ▼
  ├──► Core            models, service protocols, workspace state. No UI, no I/O.
  │       ▲
  └──► Services        protocol implementations: disk, git, PTYs, persistence, Rust
              │
              ▼
          RustBridge   Swift bindings for packages/syntax-highlighter
```

### The composition root is a module, not the Xcode target

`Herder.xcodeproj` is **generated** from `project.yml` by `xcodegen`, so every file added under `Herder/` costs a `just project` run, while files under `HerderKit` are picked up by SwiftPM on their own. Composition code changes often, so it lives one level down, in `AppFeature`.

`Herder/` therefore holds `@main`, `Info.plist`, the entitlements and the asset catalog, and links exactly one product: `AppFeature`. Wherever this document says "the App target", read "the composition root", which is `AppFeature`. Nothing in the dependency rules needs the composition root to be the Xcode target — only that exactly one place names concrete service types.

`AppFeature` is **not a feature**, despite the name. It is the one HerderKit module allowed to import `Services`, and it lives at `Sources/App/` rather than under `Sources/Features/`. The name is kept because `project.yml` names the product.

### RustBridge

`RustBridge` is a role, not a target name. In Herder it is filled by the `HerderSyntaxFFI` binary target: `packages/syntax-highlighter` ships no Swift package, it builds an XCFramework, and `.binaryTarget` is how SwiftPM takes one. `Services` depends on it directly, so there is no separate wrapper target. Substitute `HerderSyntaxFFI` wherever this document and `check-boundaries.sh` say `RustBridge`.

### Dependency rules

1. **Features** may import `Core`, `DesignSystem`, component modules (`*UI`), and `TestSupport` (for previews). Nothing else from HerderKit.
2. **Features never import other features.** Cross-feature coordination goes through `Workspace` in Core. Building blocks that several features need (for example the terminal emulator view) live in a component module such as `TerminalUI`.
3. **Services** may import `Core`, `RustBridge` and `PTYSpawn`.
4. **Core** imports only `Foundation` and `Observation`. Never SwiftUI, AppKit, SwiftData, or RustBridge.
5. **Only `AppFeature`** knows concrete service types. It constructs them in `AppEnvironment`.
6. **SwiftData is not imported at all.** It is gone; state is JSON files behind `StateStore`. Reaching for a `@Model` is reintroducing a dependency the app deliberately dropped.
7. **RustBridge types never leave Services.** Services translate FFI types to Core types at the boundary.

8. **GhosttyVt types never leave `TerminalUI`.** libghostty-vt's API is not stable, so an ABI break must cost one module. `TerminalUI` translates at its boundary: what it exposes is Core and SwiftUI types, never a `GhosttyTerminal` handle.

Rules 1, 2, 3 and 5 are enforced by target dependencies in `Package.swift`. Rules 4 and 6 (and the no-singletons rule below) are enforced by `scripts/check-boundaries.sh`, which must pass before any merge. Rule 7 is enforced in review. Rule 8's import half is enforced by `check-boundaries.sh`; the types crossing is review's job, as with rule 7.

### Feature scope

Features come in two kinds, and which kind a feature is decides how it gets its state.

**Workspace-scoped** features operate inside one checkout and receive it from the environment: `Editor`, `FileTree`, `AgentSessions`, `Terminal`, `Search`. They take `@Environment(Workspace.self)` and never look up "the active workspace" themselves.

**App-scoped** features operate above any single workspace: `Repositories`, `Settings`. `Repositories` is the UI for `WorkspaceRegistry.open(_:)` and `close(_:)` and for `WindowEnvironment.activate(_:)` — it is the feature that *picks* the workspace the others run in, so it cannot be scoped to one. `CommandPalette` is app-scoped but reads the active workspace when there is one.

This mirrors the service scoping table below, and it is the rule for where a new feature goes: if it needs the registry rather than a workspace, it is app-scoped.

## Repository layout

Herder lives in a monorepo. Everything Herder-specific lives under `apps/herder/`; the syntax highlighter is a shared package at the repo root.

**Path convention:** paths in these docs are relative to `apps/herder/`, except paths starting with `packages/`, which are relative to the repo root. Run commands from `apps/herder/`.

```
<repo root>/
├── apps/
│   ├── herder/
│   │   ├── project.yml                  # source of truth for the generated Herder.xcodeproj
│   │   ├── Herder.xcodeproj             # generated and gitignored; app target only
│   │   ├── Herder/                      # app target: @main, Info.plist, entitlements, assets
│   │   ├── UITests/                     # XCTest only; Swift Testing has no UI automation
│   │   │
│   │   ├── HerderKit/
│   │   │   ├── Package.swift
│   │   │   ├── Vendor/                  # gitignored: HerderSyntaxFFI.xcframework (`just syntax`), GhosttyVt.xcframework (`just ghostty`)
│   │   │   ├── Sources/
│   │   │   │   ├── Core/
│   │   │   │   │   ├── Models/          # Sendable value types
│   │   │   │   │   ├── Services/        # service protocols
│   │   │   │   │   ├── Workspace/       # WorkspaceRegistry, Workspace, snapshots, UI state
│   │   │   │   │   ├── Repositories/    # RepositoryStore, RepositoryAccess
│   │   │   │   │   └── Persistence/     # StateStore protocol
│   │   │   │   ├── Services/
│   │   │   │   │   ├── FileSystem/
│   │   │   │   │   ├── Git/
│   │   │   │   │   ├── Process/         # PTY spawning
│   │   │   │   │   ├── Agents/
│   │   │   │   │   ├── Highlighting/    # wraps the syntax-highlighter bindings
│   │   │   │   │   ├── Search/
│   │   │   │   │   ├── Persistence/
│   │   │   │   │   └── Workspace/       # WorkspaceServicesFactory implementation
│   │   │   │   ├── PTYSpawn/            # C: starts a process on a PTY. Imported by Services only
│   │   │   │   ├── DesignSystem/        # Liquid Glass components, tokens, icons
│   │   │   │   ├── TestSupport/         # fakes for every service protocol (#if DEBUG)
│   │   │   │   ├── Components/
│   │   │   │   │   └── TerminalUI/      # shared building blocks, module <Name>UI; the only importer of GhosttyVt
│   │   │   │   ├── Features/
│   │   │   │   │   ├── Editor/          # module EditorFeature
│   │   │   │   │   ├── FileTree/        # module FileTreeFeature
│   │   │   │   │   ├── Repositories/    # module RepositoriesFeature
│   │   │   │   │   ├── AgentSessions/   # module AgentSessionsFeature
│   │   │   │   │   ├── Terminal/        # module TerminalFeature
│   │   │   │   │   ├── Search/          # module SearchFeature
│   │   │   │   │   ├── CommandPalette/  # module CommandPaletteFeature
│   │   │   │   │   └── Settings/        # module SettingsFeature
│   │   │   │   └── App/                 # module AppFeature: the composition root
│   │   │   └── Tests/
│   │   │       ├── CoreTests/
│   │   │       ├── ServicesTests/
│   │   │       └── Features/<Name>FeatureTests/
│   │   │
│   │   ├── scripts/
│   │   │   └── check-boundaries.sh
│   │   ├── justfile
│   │   ├── AGENTS.md                    # points here; holds only what is not in this file
│   │   └── docs/
│   │       └── ARCHITECTURE.md          # this file
│   └── ...                              # other apps: not Herder's business
│
└── packages/
    ├── syntax-highlighter/              # Rust highlighter: stays here, owns its own build
    ├── ghostty-vt/                      # a pinned Ghostty commit and the recipe that builds libghostty-vt
    └── ...                              # other shared packages
```

HerderKit lives inside `apps/herder/` because nothing outside Herder uses it. If another app ever needs part of it, that part moves to `packages/` then, not before.

### Naming

- Feature folders are `Sources/Features/<Name>/`; the module is `<Name>Feature`. The suffix avoids module/type name collisions (a `FileTree` type inside a `FileTree` module confuses the compiler). The folder does **not** repeat the suffix: `Sources/Features/Editor/`, not `Sources/Features/EditorFeature/`.
- Component folders are `Sources/Components/<Name>UI/`; the module is `<Name>UI`.
- One primary type per file, and the file is named after that type.

### Package.swift template

```swift
// swift-tools-version: 6.2
import PackageDescription

/// Settings for modules that own UI. Defaulting isolation to `MainActor` keeps
/// `@MainActor` annotations out of views and `@Observable` models.
let ui: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

/// Settings for modules that must stay free to run off the main actor.
let core: [SwiftSetting] = [
    .defaultIsolation(nil),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let icons: Target.Dependency = .product(name: "PhosphorSwift", package: "swift")

func feature(_ name: String, extraDeps: [Target.Dependency] = []) -> Target {
    .target(
        name: "\(name)Feature",
        dependencies: ["Core", "DesignSystem", "TestSupport"] + extraDeps,
        path: "Sources/Features/\(name)",
        swiftSettings: ui
    )
}

let package = Package(
    name: "HerderKit",
    platforms: [.macOS(.v26)],
    products: [
        // One product. The app target links the composition root and nothing else.
        .library(name: "AppFeature", targets: ["AppFeature"]),
    ],
    dependencies: [
        .package(url: "https://github.com/phosphor-icons/swift", from: "2.1.0"),
    ],
    targets: [
        // Models, service protocols and app state. Nonisolated by default; the
        // stores under Sources/Core are marked @MainActor explicitly.
        .target(name: "Core", swiftSettings: core),

        // Protocol implementations. The only module that touches the FFI.
        .target(name: "Services", dependencies: ["Core", "HerderSyntaxFFI", "PTYSpawn"], swiftSettings: core),

        // C, because starting a process on a PTY takes a fork.
        .target(name: "PTYSpawn"),

        // The Rust highlighter. A build artifact, not a checked-in one: `just
        // syntax` in apps/herder produces it, and a fresh clone has to run
        // `just bootstrap` before this package will resolve.
        .binaryTarget(name: "HerderSyntaxFFI", path: "Vendor/HerderSyntaxFFI.xcframework"),

        // `Core` for the environment keys carrying Core's action types across
        // the App/feature boundary, which Core cannot declare itself because it
        // may not import SwiftUI. No design token knows about a workspace.
        .target(name: "DesignSystem", dependencies: ["Core", icons], swiftSettings: ui),
        .target(name: "TestSupport", dependencies: ["Core"], swiftSettings: core),
        .target(name: "TerminalUI", dependencies: ["Core", "DesignSystem"],
                path: "Sources/Components/TerminalUI", swiftSettings: ui),

        feature("Editor"),
        feature("FileTree", extraDeps: [icons]),
        feature("Repositories", extraDeps: [icons]),
        feature("Terminal", extraDeps: ["TerminalUI"]),
        feature("AgentSessions", extraDeps: ["TerminalUI"]),
        feature("Search"),
        feature("CommandPalette"),
        feature("Settings"),

        // Composition root, not a feature: the one module that names concrete
        // service types, and so the one that may import Services.
        .target(
            name: "AppFeature",
            dependencies: [
                "Core", "Services", "DesignSystem", "TestSupport",
                "EditorFeature", "FileTreeFeature", "RepositoriesFeature",
            ],
            path: "Sources/App",
            swiftSettings: ui
        ),

        .testTarget(name: "CoreTests", dependencies: ["Core", "TestSupport"], swiftSettings: core),
        .testTarget(name: "ServicesTests", dependencies: ["Services", "TestSupport"], swiftSettings: core),
    ]
)
```

Each feature's test target takes `path: "Tests/Features/<Name>FeatureTests"`. SwiftPM looks directly under `Sources` and `Tests` by default, so a target without an explicit `path` is not found.

## State

### Hierarchy

Two app-wide things, because Herder's model has two levels: the repositories the user has adopted, and the checkouts currently open. A third thing is per window, and is what makes the first two usable from more than one window at once.

```
RepositoryStore            app-wide state, not a service: the pool of folders the
                           user has adopted (Core/Repositories)
 └── Repository            one adopted repository. Persisted: name, bookmark.
                           Has N git worktrees. Says nothing about where it
                           is listed.

WorkspaceRegistry          app-wide, one per process (Core)
 └── Workspace             one checkout: a repository's worktree, or a plain folder
      ├── (DocumentStore       lives on each window's EditorModel, not here:
      │                        see "Editor surface")
      ├── git state            branch, status
      └── UI state bag         per-feature UI state (see below)

WindowEnvironment          one per window (AppFeature). Persisted as WindowSnapshot.
 ├── id                    names the window across launches
 ├── WindowRepositories    the repositories this window lists, in its order,
 │                         each with whether it is folded here (Core)
 ├── openWorkspaces        the checkouts this window keeps open
 ├── activeWorkspaceID     which one it is showing
 └── RepositoriesModel, FileTreeModel, EditorModel
                           the models behind its panes
```

`Repository` is what the user adds and names; a window arranges it, in its own `WindowRepositories`; `Workspace` is what a pane shows. One `Repository` can have several `Workspace`s open at once, one per worktree. A plain folder that is not a repository is still a `Workspace`.

**`WorkspaceID` is the canonical path of the folder, not a generated id.** A workspace *is* a folder, so the folder identifies it; a `UUID` would have to be persisted beside the path and kept in step with it, and all it would buy is surviving a move — which for a checkout means a different checkout. `Repository` is the level that genuinely needs identity independent of its path, because the user names it and its bookmark follows the folder around, which is why that one has a `UUID` and this does not.

### Rules

- **`Workspace` is the single source of truth for one checkout.** If two places hold the same fact, one of them is a bug.
- **Switching workspaces or worktrees changes `WindowEnvironment.activeWorkspaceID` and nothing else.** Never tear down documents, terminals, or agent sessions on a switch. Background worktrees keep running.
- **"Active" is per window, not global.** Multiple windows can show different workspaces, and each has its own editor, file tree and sidebar models. A click in one window must not be visible in another.
- **A workspace lives while any window holds it.** A window holds the workspaces in its `openWorkspaces` by passing itself as `holder` to `open(_:holder:)` and `close(_:holder:)`; the registry drops one only when the last holder lets go. Showing and holding are different sets — switching away from a workspace does not let go of it. A window closing calls `release(holder:)`.
- Opening and closing go through `WorkspaceRegistry.open(_:holder:)` and `close(_:holder:)`. Opening is idempotent; nothing but `close(_:)` ever drops a workspace. Closing must prompt for dirty documents and running agents.
- **A workspace drains only while a frontmost window is showing it.** Holding a worktree open costs a file watcher; *refreshing* it costs a `git status` for the whole repository, so only what is on screen refreshes. Background workspaces accumulate their events and act on them in one go when they come forward. Windows declare what they show with `display(_:from:)`, keyed by window identity rather than counted, so saying it twice is harmless.
- **No cap on how many workspaces are held.** A cap means closing one the user did not ask to close. If it becomes a problem, the answer is a visible "close worktree", not an eviction they cannot see.
- Stores are `@MainActor @Observable public final class` with `public private(set)` state. Mutation happens only through methods (`workspace.documents.open(url)`, never `workspace.documents.tabs.append(...)`).
- Features receive their `Workspace` from the environment (`@Environment(Workspace.self)`). They never look up "the active workspace" themselves.
- Keep stores small and focused so Observation tracking stays precise. No god objects.
- **Key paths with `PathKey`, never with a raw `URL`.** The same folder arrives spelled differently from a bookmark, from `git` and from the file watcher, and `standardizedFileURL` does not resolve symlinks. A dictionary keyed on `URL` looks like it works and silently misses.

```swift
// AppFeature: root view resolves and injects
if let workspace = registry.workspace(for: window.activeWorkspaceID) {
    WorkspaceView()
        .environment(workspace)
}
```

### How a feature changes the active workspace

Reading is free: a feature takes `@Environment(Workspace.self)` and gets whatever this window resolved. Nothing asks "which one is active?", which is what keeps two windows from disagreeing.

Writing cannot be, because `WindowEnvironment` is in the App target and no feature may import it. So a feature says what it wants through `OpenWorkspaceAction` — declared in `Core`, supplied by App as an environment value, and shaped like SwiftUI's `openWindow`:

```swift
// RepositoriesFeature
@Environment(\.openWorkspace) private var openWorkspace
...
.onTapGesture { openWorkspace(WorkspaceID(worktree.path)) }
```

The `@Entry` declaring the key is in `DesignSystem`, which is the one module every feature already has that may import SwiftUI. That is also why `DesignSystem` depends on `Core`: for the action types, not for anything a design token knows about.

### Per-workspace UI state

Anything that must survive a workspace switch (scroll position, expanded folders, selected tab, split layout) cannot live in `@State`, because SwiftUI discards it when the view swaps out. Features define their own UI state types and store them on the workspace without Core knowing the concrete types:

```swift
// Core/Workspace/WorkspaceUIState.swift
@MainActor public protocol WorkspaceUIState: AnyObject { init() }

/// Optional: conform when the state should also survive relaunch.
@MainActor public protocol PersistedWorkspaceUIState: WorkspaceUIState {
    static var persistenceKey: String { get }
    func encode() throws -> Data
    func restore(from data: Data) throws
}

extension Workspace {
    /// Lazily creates and caches one instance per type for this workspace.
    /// A restored snapshot is applied here, on first ask.
    public func uiState<S: WorkspaceUIState>(_ type: S.Type = S.self) -> S

    public var snapshot: WorkspaceSnapshot { get }
    public func restore(from snapshot: WorkspaceSnapshot)
}

// FileTreeFeature
@Observable final class FileTreeUIState: WorkspaceUIState {
    var expanded: Set<PathKey> = []
    required init() {}
}
```

**Restoring happens on first ask, not at launch.** `restore(from:)` holds the snapshot's `uiState` blobs; the feature's instance is made and filled the first time something asks for it. That is what lets a workspace restore state for features Core knows nothing about. State nobody asks for this session is never decoded and is written back out unchanged, so closing a workspace without opening a pane does not forget that pane's layout.

## Services

- Protocols live in `Core/Services/`. Implementations live in `Services/<Area>/`. Every protocol has a fake in `TestSupport/Fakes/`, wrapped in `#if DEBUG` so a release build links an empty module.
- **Pure logic that happens to be about an external system still belongs in `Core`.** `GitRefName` validates a branch name and `GitWorktreeLocation` works out where a worktree goes: both are string and URL arithmetic with no I/O, and a feature needs them to refuse a name as it is typed. Only the code that actually runs `git` is a service.
- Stateful services are `actor`s. Stateless ones are `Sendable` structs.
- Services never hold references to views or view models.
- Services report changes into the `Workspace` by calling its `@MainActor` methods. Views read from `Workspace` and feature models; they never call services for data. Feature models call services to perform actions.

### Scoping

| App-scoped (built once in `AppEnvironment`) | Workspace-scoped (built per workspace by `WorkspaceServicesFactory`) |
|---|---|
| Settings, keybindings, theme | File system + FSEvents watcher |
| `HighlightService` (Rust syntax engine) | Git |
| `StateStore` | Search |
| Bookmarks, folder picker | Process / PTY |
| | Agent runner |

Workspace-scoped services are created when a workspace opens and torn down when it closes. Each one is bound to its workspace root, so there's never a question of which repo it's talking to.

### Dependency injection

`AppEnvironment` constructs services and passes them in through initializers or SwiftUI `@Entry` environment values. No `static let shared` singletons anywhere in HerderKit.

## Persistence

- The source of truth for code is the disk and git. Herder persists only its own app state.
- `StateStore` (protocol in Core) loads and saves `Codable & Sendable` values by key.
- Live `@Observable` state converts to and from snapshot structs (`AppSnapshot`, `WorkspaceSnapshot`). Never make `@Observable` classes `Codable` directly; the macro's underscored backing storage leaks into the encoded keys.
- Snapshots carry a `version` field. New fields use `decodeIfPresent` with defaults. That's the whole migration strategy.
- Saves are debounced (a few hundred milliseconds after changes settle) **by their callers, not by the store**. A workspace waits 400ms after its UI state settles; the repository list does not wait at all, for the reason two lines down. A debounce inside `StateStore` would flatten that distinction and delay the one thing that must not be delayed. Writes are atomic.
- **Nothing is saved on termination.** `willTerminate` is a synchronous callback and writing is not, so a task started there races the process exiting. The debounce is short for that reason. If a change ever matters enough to guarantee, the answer is `applicationShouldTerminate` returning `.terminateLater`, not a save in `stop()`.
- The repository list is the exception: it saves immediately on every change, because each addition mints a security-scoped bookmark that cannot be remade.
- **A window is remembered by a `WindowSnapshot`, found by an id kept in `@SceneStorage`.** The scene storage holds that id and nothing else: it only comes back when the system restores the scene, so everything that has to survive lives in the snapshot. The snapshot is the repositories the window lists (with each one's fold), the workspaces it keeps open, and the one it shows. `AppSnapshot` holds only the pool of repositories and `windows`, an index of which snapshots exist, most recently used first. If something about a window is in `AppSnapshot` beyond that index, the split has not held.
- **A window with no stored id adopts the one used last, if no other window is open; otherwise it is blank.** Quitting with every window closed loses all the scene storage, and a relaunch that opened blank would look like the app forgot everything. With another window open, a new window is ⌘N and is a blank slate. This is decided in `AppEnvironment.claimWindow(id:)` with no suspension between the decision and recording it, so two windows appearing at once cannot adopt the same snapshot. All of it waits for `start()`, which is where folder access is taken.
- **A window's snapshot is deleted when the user closes it, not when the app quits.** `WindowChrome` reports `NSWindow.willCloseNotification`, which AppKit does not post while terminating. That is an assumption about AppKit and wants checking by hand: quit with two windows open and look for both under `windows/` on relaunch. The index is capped at `WindowStore.maxWindows`, least recently used first, so a close that is missed leaks a bounded number of small files. The **last** window's snapshot is kept when it closes, so that closing everything is not the same as forgetting everything.
- **A window with nothing in it is not saved.** It would be the most recently used and so the one a relaunch adopted.
- **Every write to `AppSnapshot` goes through `AppSnapshotStore`.** The repository list and the window index share that key and each change reads the whole snapshot, edits its part and writes it back; two at once would lose a field, and the field could be the bookmarks. `AppSnapshotStore` queues them.
- **Taking a repository out of a window is not forgetting it.** `WindowRepositories.remove(_:)` changes the window's membership only; the record, its bookmark and its folder access stay in the pool. Adding a folder the pool already has joins the existing record rather than minting a second bookmark. The cost is that a repository no window lists can only be got back by picking its folder again, which works but is clumsy; a list of what was adopted before belongs in the add modal and is not built.
- Which files a workspace had open is `EditorUIState`, under `"editor.openFile"`, in that workspace's snapshot. It is the workspace's, not the window's, so switching away and back restores it too. A file that has gone from disk stays remembered and is shown struck through; only closing its tab forgets it. The key still says `openFile` because it is a file name on the user's disk: the tab list arrived as fields inside the stored object, which is the shape it was given for exactly this, and a build that wrote one `file` still decodes as a single tab.
- Agent transcripts and sessions are not stored by Herder: each agent keeps its own, and Herder remembers only the agents the user added, and which was used last.
- **Secrets go in the Keychain, never a file. A capability is not a secret.** A credential that grants access to something otherwise out of reach — an API token — is a secret. A security-scoped bookmark is a handle to a folder the user themselves picked, sitting in a file in their own home directory, and anything running as them can already read that folder without it. So the bookmark lives in `state.json` as base64, where it stays in one atomic write with the record it belongs to. Splitting it out would put one repository in two stores and double the window in which a crash leaves a record with no bookmark.
- Searchable indexes and history, when needed, use SQLite on the Rust side.

### A name that reaches disk cannot be renamed by a rename

There is no SwiftData left, so the specific rule this section held — never rename a `@Model` class — no longer has anything to apply to. It is kept because the lesson outlived the technology, and because of how it was learned.

**What happened.** A task billed as a pure rename with no behaviour change renamed the `@Model` class `Workspace` to `Repository`. But a `@Model` class name *is* the stored entity name: SwiftData derives the SQLite table from it and records the schema the store was written against. The store on disk had a `ZWORKSPACE` table recorded against a schema saying `Workspace`; after the rename the schema described an entity called `Repository`, so the store matched no version in the migration plan and SwiftData refused to open it at all — `Cannot use staged migration with an unknown model version`, on launch, with every adopted folder and every security-scoped bookmark behind it unreachable. The fix was to keep the persisted class called `Workspace` with a `typealias Repository` over it: the vocabulary the code wanted, over the name the store had recorded.

**Why nothing caught it**, which is the part worth keeping. Every storage test used an in-memory container, and an in-memory container is created at the current version every time, so it can never disagree with the code. The first test written for the bug was no better: it built its "old" store from today's schema, so both sides moved together and it passed under the bug. The test that caught it was a real store, written by an earlier build, committed as a fixture and generated by nothing.

The general form: **an identifier that is also a key on disk is data, and renaming it is a migration.** What is left in the codebase that this still binds:

- `PersistedWorkspaceUIState.persistenceKey`. The file tree's is still `"explorer.expanded"` after the feature was renamed to `FileTreeFeature`, because changing it would leave every saved blob unreachable and close every folder the user had open. The editor's is `"editor.openFile"`, an object with one field rather than a bare path — and that is what let tabs arrive as `files` and `active` beside the original `file`, which is still read and no longer written. The key kept the singular name it was born with, which is the rule working rather than the rule chafing.
- `AppSnapshot.persistenceKey` and the file names derived from `WorkspaceSnapshot.persistenceKey(for:)`.
- `WindowSnapshot`'s `paneWidths`, an object of `leading` and `trailing`, each absent until that pane has been dragged.
- `Codable` `CodingKeys` on any snapshot. Renaming a property renames the JSON field; add a new one with `decodeIfPresent` instead.

And the test rule, which also outlived SwiftData: **storage changes are tested against bytes this build did not write.** A fixture encoded by the current types proves nothing, because both sides move together.

### A `Repository` cannot be recreated from disk

`Repository` holds a **security-scoped bookmark**, plus a user-chosen name. None of that is recoverable from disk or git: the bookmark cannot be regenerated without the user re-picking the folder in an `NSOpenPanel`. So the repository list is the one piece of Herder's state where losing the store costs the user real work. It saves immediately on every change, it is written in one atomic write with the bookmark inside it, and `RepositoryStore.save()` reads the key before writing it so that nothing sharing the key can drop it.

The bookmark's storage was an open question for a long time. It is settled: base64 in `state.json`, for the reason in the list above.

### Implementation

`FileStateStore` in `Services/Persistence/`, writing JSON. `PersistenceStack` is the seam in front of it, and the reason the SwiftData store it replaced could be deleted rather than unpicked: `AppEnvironment` has never named a storage type.

```
~/Library/Application Support/Herder/
├── state.json                       # AppSnapshot: adopted repositories, index of windows
├── windows/<id>-<hash>.json         # WindowSnapshot: repositories listed, workspaces open and shown
└── workspaces/<name>-<hash>.json    # WorkspaceSnapshot: tabs, UI state
```

**The file name is not the id.** A `WorkspaceID` is an absolute path, which cannot be a file name: it contains separators, and a deep enough one runs past the 255-byte limit and fails the save. So the name is the last path component — readable, so the directory can be looked through by eye — plus six bytes of SHA-256 of the whole key, because two worktrees called `main` under different repositories would otherwise overwrite each other. **SHA-256 and not `hashValue`:** Swift's hashing is seeded per process, so a store built on it would look for every file under a name it had never written.

This is the shape it grows into, not the shape it has. Fields arrive with the features that need them — an editor showing one read-only file has no tab list to write down — as new fields with defaults, decoded with `decodeIfPresent`. Today it is `version`, `id` and `uiState`. There is no separate `root`: the id *is* the path.

```swift
public struct WorkspaceSnapshot: Codable, Sendable {
    public var version = 1
    public var id: WorkspaceID
    public var uiState: [String: Data]   // keyed by PersistedWorkspaceUIState.persistenceKey
}
```

### The editor's tabs are the editor's UI state, not Core's

This snapshot held `openTabs` and `activeTab` as fields of its own before the
tab bar was built. They went in `EditorUIState` instead, under
`"editor.openFile"`, and the rule that decides it is the one already written
down: **live state two features both read goes in Core**. Only the editor reads
its tab list. A `DocumentStore` in Core becomes the right home the day a
document can be dirty, because then the sidebar, the close prompt and the
command palette all need to know — and dirtiness is the thing that forces it,
not tabness.

The split that stands is the one the single open file already had. The *live*
set belongs to `EditorModel`, which is per window, so two windows on one
checkout keep independent bars and a click in one is not visible in the other.
The *remembered* set belongs to the workspace, so switching away and back
restores it and so does a relaunch. Only the tab showing is ever read from
disk; a background tab is a name until it is clicked, including one whose file
has gone, which is the same argument as a workspace not draining until a window
shows it.

## Concurrency

- Swift 6 language mode everywhere. Zero concurrency warnings.
- `NonisolatedNonsendingByDefault` is enabled on every target. Without it a plain `nonisolated` async function runs on whichever actor called it, so `@concurrent` is what asks for the global executor — which is how the highlighter parses a megabyte without stopping the editor from redrawing.
- `Features`, components, `DesignSystem` and `AppFeature` use `.defaultIsolation(MainActor.self)`. `Core` and `Services` keep the nonisolated default; stores in Core are marked `@MainActor` explicitly.
- Prefer structured concurrency: `async`/`await`, task groups, and SwiftUI's `.task(id:)` for view-tied work so it cancels automatically.
- No new `DispatchQueue` usage and no completion-handler APIs in new code. The two that exist are at a C or AppKit boundary with no `async` equivalent (FSEvents needs a dispatch queue; the line-number gutter defers `needsDisplay` out of a layout pass) and carry a `// CONCURRENCY:` comment.
- Escape hatches (`@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency import`) require a `// CONCURRENCY:` comment on the same or preceding line explaining why it's safe.

## Rust

- The syntax highlighter lives in `packages/syntax-highlighter` and stays there. Don't move it, rename it, or restructure its crates as part of other work.
- It owns its build and binding generation. HerderKit consumes its output; HerderKit doesn't reach into its internals or duplicate its build steps. `just syntax` builds the XCFramework and copies it into `HerderKit/Vendor/`, so the `.binaryTarget` path stays inside the package and SwiftPM never depends on Cargo's output directory.
- **The bindings are hand-written**, not generated: a C header and a modulemap in `packages/syntax-highlighter/include/`, declaring module `HerderSyntaxFFI`. The header is the API. It is edited by hand, in step with `src/lib.rs`, and the two must not drift — `TreeSitterHighlighterTests` asserts the kind count matches.
- Changes to its public API (what Swift sees) are deliberate and get their own task.
- Swift touches it in exactly one place: the highlighting service in `Services/Highlighting/` (for example `RustHighlightService`), which converts its types to Core types.
- Keep the FFI API coarse: send edits, not whole documents; request highlights for the visible range; batch where possible.
- Any future Rust work (text ropes, file search) goes in its own package alongside it, as `packages/<name>`, following the same rules.
- **Offsets:** Core types use UTF-16 offsets to match `NSString` and TextKit. Tree-sitter works in UTF-8 bytes. **The crate converts before handing tokens over**, because a conversion a caller has to remember is one a caller will forget. There is no conversion on the Swift side, and there must not be a second one.

## Editor surface

- `NSTextView` with TextKit 2, wrapped in `NSViewRepresentable`. Not SwiftUI's `TextEditor`.
- Syntax highlighting is applied with `NSTextLayoutManager` rendering attributes, not text storage attributes. It's faster and keeps highlighting out of the undo stack.
- Text contents live in `NSTextStorage` and the Rust rope mirror. `Document` holds metadata (URL, language, dirty flag, buffer handle), not the text itself.
- **Keep token kinds and colours apart.** `Core` says what a span of code *is* and names no colour; `DesignSystem` holds the colours and knows no kinds; `EditorFeature` is the one place that pairs them. That is what lets a grammar be added without touching the theme, and the theme be changed without touching a grammar.
- **Tokens are only ever applied to the string they were found in.** `SourceText` binds text to its tokens so the pair cannot come apart, and the editor model checks the text still matches before letting a highlight land. Colour does arrive after the text — a quarter of a second of query compilation must not sit between a click and the file appearing — and that is safe only because of those two things. A `SourceText` with no tokens is incomplete; one with another string's tokens paints the wrong characters, or throws.
- **A reload that finds the same text must change nothing.** The worktree notifies every observer when any folder in it is read, so expanding a folder in the file tree reloads the open file. Compare the text, not the whole content value: a freshly read one carries no tokens yet, so comparing values drops the colour already on screen and flickers it back.
- **A tab is a `Document` and a `Buffer`.** `Document` (Core) holds the file's `baseline`, the text as the disk last had it, and compares the buffer and every disk read against it. The `Buffer` (`EditorFeature/Platform`) owns the `NSTextStorage`, the layout, the view and the `UndoManager`, and is reached from Core only by `BufferHandle`. A tab switch swaps which pane is mounted, so undo, selection and scroll position survive it. Documents are made when a tab is first shown, not at launch.
- **A disk read under unsaved edits never replaces them.** The document is marked stale instead. Our own save needs no suppression: it reads back equal to the baseline.
- **Saves are explicit and byte-faithful.** ⌘S writes the buffer as it is — no trailing newline, no trimming, no line-ending changes — and nothing else writes. A failed save keeps the document dirty and says why. A deleted file is written back; its missing folder is not.
- **Unsaved text is never persisted.** The tab list is remembered; buffer contents are not. Losing it takes an answer: ⌘W on a dirty tab asks about that tab, closing a window asks once for all of its dirty files, and quitting asks once for every window's. Each is Save / Don't Save / Cancel, and a save that fails cancels what it was part of. The window and quit prompts are AppKit (`CloseGuard` in front of SwiftUI's window delegate, and `AppDelegate`), because SwiftUI has no hook for either.
- **A stale buffer waits for the person.** The pane shows Reload (take the disk, lose the edits) or Keep Mine (stay dirty, and saving then replaces the disk). Neither is the default.
- **Two dirty documents moved onto one path are both kept**, but only one is reachable: tabs are keyed by `PathKey`, so they share one. Both still count as unsaved and are listed by the prompts. Giving each its own tab means keying tabs by `BufferHandle`, which nothing has needed yet.
- **The `DocumentStore` is per window, on `EditorModel`, not on `Workspace`.** A buffer belongs to the window that made it, so a store shared across windows would hold documents whose buffers only one of them has.

## Agents and terminal

- PTY management lives in `Services/Process/`. The terminal emulator view lives in `Components/TerminalUI/`.
- **Starting a process on a PTY is C, in the `PTYSpawn` target**, and nothing else is. The child needs the terminal as its *controlling* terminal, or a resize sends no SIGWINCH and closing the terminal hangs up nobody. macOS's `posix_spawn` cannot do that: it opens files before it starts the new session. That takes a `fork`, and Swift cannot run safely between a fork and an exec. `herder_pty_spawn` forks, calls `setsid` and `TIOCSCTTY`, then execs in place with `POSIX_SPAWN_SETEXEC`. Only `Services` imports it.
- `TerminalFeature` and `AgentSessionsFeature` both build on `TerminalUI`.
- **An agent session is an agent's own terminal UI in a PTY**: the agent's command, run as `exec <command>` through the user's login shell (`ShellLaunch.command`) in a worktree's root. Herder does not talk to any agent: no server client, and no session list beyond what this window has open. That is what lets Claude Code, Codex, opencode and Pi sit side by side, and an agent Herder has never heard of be added as a name and a command.
- The agents are an `Agent` (id, name, command, optional resume command and session lookup) each, in the app-wide `AgentCatalog` (`Core/Agents`). The presets are code (`Agent.presets`), so a new one reaches everybody; the user's own and the one used last are an `AgentsSnapshot` under the `"agents"` key, edited in the Agents pane in Settings. A session started without naming an agent uses the one used last.
- The panel (`AgentPanelModel`) is per window and per workspace, like the terminal's tabs. Switching workspaces never ends a session; closing a tab ends it, and closing a window ends its processes but not its sessions. The panel is always on screen and cannot be hidden.
- **Open sessions persist and are resumed.** `AgentPanelUIState` keeps each tab's id and a copy of its `Agent` on the workspace. A reopened tab comes back paused and runs the agent's `resumeCommand` when shown: the one in front at once, the rest when clicked, so a reopened window does not start every agent at once. `{session}` in a command stands for the session's id. Claude Code and Pi are given one Herder mints, up front. opencode names its own, so its agent has a `sessionLookup` command (`CommandClient`, run through the login shell) whose output `AgentSessionLookup` reads: the earliest session in that worktree made after the tab started and not claimed by another tab. It runs when a turn ends and again before resuming, and the id found is saved with the tab; if none is found, the tab starts afresh. Codex can do neither, and resumes the last session in the worktree. Workspaces a window holds but is not showing are restored too, so the sidebar lists their sessions. Showing a worktree with nothing remembered starts nothing.
- **The sidebar lists each window's open sessions under their worktree**, through `OpenAgentSessions` (Core, one per window): the panel writes `AgentSessionSummary`s into it and the sidebar reads it from the environment. What a session seems to be doing is read off its terminal, the same for every agent: the title it sets (OSC 0/2, minus any leading spinner), output in the last sample that typing does not explain (working), and a notification (OSC 9/777) or bell nothing has been typed since (needs input). `TerminalUI` exposes these as plain counts and values, never as GhosttyVt types. Clicking a listed session goes through `ShowAgentSessionAction`.
- The sidebar starts a session, with an agent or the one used last, through `StartAgentSessionAction` (Core, with its environment key in `DesignSystem`); it reads the catalog from the environment, since the sidebar and the panel are two features that cannot see each other. The window's `startAgentSession(in:)` switches workspace and asks the panel, which holds the request until that workspace is showing.
- The panel's width is a layout choice, so it is the window's: `PaneWidths.agent`, beside the outer panes. It sits between the sidebar and the editor, and the window's minimum width includes it.

## Testing and previews

- Unit tests use Swift Testing (`import Testing`): structs for suites, `#require` to unwrap, `#expect` for everything else. They run in parallel, so anything process-global needs a unique path per test.
- Core and Services have unit tests. Feature models are tested against fakes from `TestSupport`.
- Previews use fakes: `.environment(Workspace.preview())`.
- The syntax highlighter is tested with `cargo test` and `cargo clippy` inside `packages/syntax-highlighter`. Clippy warnings are errors.

## Code conventions

- Default to `internal`. A module's `public` surface is deliberate and small; a feature usually exposes one entry view.
- Views stay dumb: layout and bindings. Logic goes in the feature model, or in a small action type (`OpenFileAction`) when the model gets heavy.
- **Observe models directly.** `@Observable` classes read straight from views, injected through `init` or `@Environment`. Reach for a separate ViewModel layer only when direct observation has actually failed.
- **Reference `Theme` instead of literals** for spacing, colour, radius and size.
- No singletons.

## Commands

Run from `apps/herder/`.

```
just bootstrap # syntax + ghostty + project. Needed once in a fresh clone, and needs Rust and Zig toolchains.
just syntax    # runs packages/syntax-highlighter's own build, then copies the XCFramework into Vendor/
just ghostty   # builds libghostty-vt at the commit in packages/ghostty-vt/GHOSTTY_COMMIT (needs Zig 0.17.x), copies it into Vendor/
just project   # xcodegen generate. Needed after changing Herder/ or UITests/, not HerderKit.
just build     # project + syntax, then xcodebuild
just test      # the Swift Testing suites, via xcodebuild
just dev       # build and run, with output in this terminal
just uitest    # the XCTest UI suite. Slow; launches the app.
just check     # scripts/check-boundaries.sh
```

`just test` goes through `xcodebuild test -scheme HerderKit-Package` rather than `swift test`, because PhosphorSwift ships its icons as an asset catalog without declaring it a resource, which only Xcode's build system bundles. `swift test` does not work here.

`build`, `test` and `bootstrap` all depend on `syntax` and `ghostty` (the latter is skipped when the framework already came from the pinned commit), because a stale static library links without complaint: the app would highlight with yesterday's grammars and nothing would say so.
