# Herder Architecture

This is the target architecture for Herder and the rulebook for anyone (human or agent) changing the code. If the code and this document disagree, assume the code is wrong. If you think the document is wrong, stop and ask Kurt rather than quietly diverging.

## Stack

- Swift 6 language mode, `swift-tools-version: 6.2`, macOS 26 and later
- SwiftUI for the app shell and panels; AppKit (`NSTextView` with TextKit 2) for the editor surface
- Rust for performance-sensitive work, starting with the syntax highlighter in `packages/syntax-highlighter`. That package stays where it is and keeps its own build and binding setup.
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

`Herder.xcodeproj` is **generated** from `project.yml` by `xcodegen`, so every file added under `Herder/` costs a `just project` run, while files under `Packages/HerderKit` are picked up by SwiftPM on their own. Composition code changes often, so it lives one level down, in `AppFeature`.

`Herder/` therefore holds `@main`, `Info.plist`, the entitlements and the asset catalog, and links exactly one product: `AppFeature`. Wherever this document says "the App target", read "the composition root", which is `AppFeature`. Nothing in the dependency rules needs the composition root to be the Xcode target — only that exactly one place names concrete service types.

`AppFeature` is **not a feature**, despite the name. It is the one HerderKit module allowed to import `Services`, and it lives at `Sources/App/` rather than under `Sources/Features/`. The name is kept because `project.yml` names the product.

### RustBridge

`RustBridge` is a role, not a target name. In Herder it is filled by the `HerderSyntaxFFI` binary target: `packages/syntax-highlighter` ships no Swift package, it builds an XCFramework, and `.binaryTarget` is how SwiftPM takes one. `Services` depends on it directly, so there is no separate wrapper target. Substitute `HerderSyntaxFFI` wherever this document and `check-boundaries.sh` say `RustBridge`.

### Dependency rules

1. **Features** may import `Core`, `DesignSystem`, component modules (`*UI`), and `TestSupport` (for previews). Nothing else from HerderKit.
2. **Features never import other features.** Cross-feature coordination goes through `Workspace` in Core. Building blocks that several features need (for example the terminal emulator view) live in a component module such as `TerminalUI`.
3. **Services** may import `Core` and `RustBridge`.
4. **Core** imports only `Foundation` and `Observation`. Never SwiftUI, AppKit, SwiftData, or RustBridge.
5. **Only `AppFeature`** knows concrete service types. It constructs them in `AppEnvironment`.
6. **SwiftData**, while it exists, is imported only under `Services/Persistence/`.
7. **RustBridge types never leave Services.** Services translate FFI types to Core types at the boundary.

Rules 1, 2, 3 and 5 are enforced by target dependencies in `Package.swift`. Rules 4 and 6 (and the no-singletons rule below) are enforced by `scripts/check-boundaries.sh`, which must pass before any merge. Rule 7 is enforced in review.

### Feature scope

Features come in two kinds, and which kind a feature is decides how it gets its state.

**Workspace-scoped** features operate inside one checkout and receive it from the environment: `Editor`, `FileTree`, `AgentSessions`, `Terminal`, `Search`. They take `@Environment(Workspace.self)` and never look up "the active workspace" themselves.

**App-scoped** features operate above any single workspace: `Repositories`, `Settings`. `Repositories` is the UI for `WorkspaceRegistry.open(_:)` and `close(_:)` and for setting `WindowModel.activeWorkspaceID` — it is the feature that *picks* the workspace the others run in, so it cannot be scoped to one. `CommandPalette` is app-scoped but reads the active workspace when there is one.

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
│   │   ├── Packages/HerderKit/
│   │   │   ├── Package.swift
│   │   │   ├── Vendor/                  # gitignored: HerderSyntaxFFI.xcframework, built by `just syntax`
│   │   │   ├── Sources/
│   │   │   │   ├── Core/
│   │   │   │   │   ├── Models/          # Sendable value types
│   │   │   │   │   ├── Services/        # service protocols
│   │   │   │   │   ├── Workspace/       # WorkspaceRegistry, Workspace, stores, snapshots
│   │   │   │   │   └── Persistence/     # StateStore protocol, snapshot types
│   │   │   │   ├── Services/
│   │   │   │   │   ├── FileSystem/
│   │   │   │   │   ├── Git/
│   │   │   │   │   ├── Process/         # PTY spawning
│   │   │   │   │   ├── Agents/
│   │   │   │   │   ├── Highlighting/    # wraps the syntax-highlighter bindings
│   │   │   │   │   ├── Search/
│   │   │   │   │   ├── Persistence/
│   │   │   │   │   └── Workspace/       # WorkspaceServicesFactory implementation
│   │   │   │   ├── DesignSystem/        # Liquid Glass components, tokens, icons
│   │   │   │   ├── TestSupport/         # fakes for every service protocol (#if DEBUG)
│   │   │   │   ├── Components/
│   │   │   │   │   └── TerminalUI/      # shared building blocks, module <Name>UI
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
│   │       ├── ARCHITECTURE.md          # this file
│   │       └── REALIGNMENT.md
│   └── ...                              # other apps: not Herder's business
│
└── packages/
    ├── syntax-highlighter/              # Rust highlighter: stays here, owns its own build
    └── ...                              # other shared packages
```

HerderKit lives inside `apps/herder/` because nothing outside Herder uses it. If another app ever needs part of it, that part moves to `packages/` then, not before. It sits under `Packages/` so a second local package has somewhere to go.

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
        // Models, service protocols and workspace state. Nonisolated by default;
        // the stores in Sources/Core/Workspace are marked @MainActor explicitly.
        .target(name: "Core", swiftSettings: core),

        // Protocol implementations. The only module that touches the FFI.
        .target(name: "Services", dependencies: ["Core", "HerderSyntaxFFI"], swiftSettings: core),

        // The Rust highlighter. A build artifact, not a checked-in one: `just
        // syntax` in apps/herder produces it, and a fresh clone has to run
        // `just bootstrap` before this package will resolve.
        .binaryTarget(name: "HerderSyntaxFFI", path: "Vendor/HerderSyntaxFFI.xcframework"),

        .target(name: "DesignSystem", dependencies: [icons], swiftSettings: ui),
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

Two app-wide things, because Herder's model has two levels: the repositories the user has adopted, and the checkouts currently open.

```
RepositoryStore            app-wide state, not a service: the folders the
                           user has adopted (Core/Repositories)
 └── Repository            one adopted repository. Persisted: name, bookmark,
                           sidebar order. Has N git worktrees.

WorkspaceRegistry          app-wide, one per process (Core)
 └── Workspace             one checkout: a repository's worktree, or a plain folder
      ├── DocumentStore        open documents, tabs, dirty state
      ├── AgentSessionStore    agent sessions running in this worktree
      ├── git state            branch, status
      └── UI state bag         per-feature UI state (see below)

WindowModel                one per window (AppFeature)
 └── activeWorkspaceID     which workspace this window is showing
```

`Repository` is what the user adds and names and arranges; `Workspace` is what a pane shows. One `Repository` can have several `Workspace`s open at once, one per worktree. A plain folder that is not a repository is still a `Workspace`.

**`WorkspaceID` is the canonical path of the folder, not a generated id.** A workspace *is* a folder, so the folder identifies it; a `UUID` would have to be persisted beside the path and kept in step with it, and all it would buy is surviving a move — which for a checkout means a different checkout. `Repository` is the level that genuinely needs identity independent of its path, because the user names it and its bookmark follows the folder around, which is why that one has a `UUID` and this does not.

### Rules

- **`Workspace` is the single source of truth for one checkout.** If two places hold the same fact, one of them is a bug.
- **Switching workspaces or worktrees changes `WindowModel.activeWorkspaceID` and nothing else.** Never tear down documents, terminals, or agent sessions on a switch. Background worktrees keep running.
- **"Active" is per window, not global.** Multiple windows can show different workspaces.
- Opening and closing go through `WorkspaceRegistry.open(_:)` and `close(_:)`. Closing must prompt for dirty documents and running agents.
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

Writing cannot be, because `WindowModel` is in the App target and no feature may import it. So a feature says what it wants through `OpenWorkspaceAction` — declared in `Core`, supplied by App as an environment value, and shaped like SwiftUI's `openWindow`:

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
- Saves are debounced (a few hundred milliseconds after changes settle). Writes are atomic.
- **Nothing is saved on termination.** `willTerminate` is a synchronous callback and writing is not, so a task started there races the process exiting. The debounce is short for that reason. If a change ever matters enough to guarantee, the answer is `applicationShouldTerminate` returning `.terminateLater`, not a save in `stop()`.
- The repository list is the exception: it saves immediately on every change, because each addition mints a security-scoped bookmark that cannot be remade.
- Which workspace a window shows is stored with `@SceneStorage`.
- Agent transcripts are not stored by Herder. Store an `AgentSessionRef` (the Claude Code session ID plus any Herder label) so sessions can be resumed.
- Secrets go in the Keychain, never a file.
- Searchable indexes and history, when needed, use SQLite on the Rust side.

### Never rename a `@Model` class

**The class name is the stored entity name.** SwiftData derives the SQLite table from it, and the store records the schema it was written against. Renaming the class renames the entity, so the existing store becomes a version the migration plan has never heard of — SwiftData refuses it with "Cannot use staged migration with an unknown model version" and every row is unreachable. The data is still in the file; nothing in the app can read it.

This has already happened once: see `realignment/notes.md`. The repository model is therefore still the class `Workspace` inside `WorkspaceSchemaV1`, with `Repository` as a typealias over it — the vocabulary the architecture wants, over the name the store recorded.

Two rules follow:

- A `@Model` is renamed only with a `custom` migration stage that copies the rows, and never as part of other work.
- **Schema changes are tested against a store this build did not write.** An in-memory container is created at the current version every time, so it cannot catch a change that strands what is already on the user's disk. `StorageTests` keeps a committed V1 store as a fixture for exactly this; a test that builds its "old" store from today's schema proves nothing, because both sides move together.

### A `Repository` cannot be recreated from disk

`Repository` holds a **security-scoped bookmark**, plus a user-chosen name and sidebar order. None of that is recoverable from disk or git: the bookmark cannot be regenerated without the user re-picking the folder in an `NSOpenPanel`. So the repository list is the one piece of Herder's state where losing the store costs the user real work, and it gets a migration rather than a fresh start whenever its storage changes. Where the bookmark lives once `FileStateStore` lands is still open — see `REALIGNMENT.md`.

### Implementations

- **Transitional:** `SwiftDataStateStore` in `Services/Persistence/`, storing snapshot JSON blobs in a single `@Model`. `PersistenceStack` is the seam in front of it: it hands back a `StateStore`, and the `ModelContainer` never leaves the module. That is what keeps `import SwiftData` out of the App target, and what makes the swap below a new type rather than a change to `AppEnvironment`.
- **Target:** `FileStateStore` writing JSON:

```
~/Library/Application Support/Herder/
├── state.json                  # AppSnapshot: adopted repositories, open workspaces, recents
└── workspaces/<id>.json        # WorkspaceSnapshot: tabs, UI state, agent session refs
```

This is the shape it grows into, not the shape it has. Fields arrive with the features that need them — an editor showing one read-only file has no tab list to write down — as new fields with defaults, decoded with `decodeIfPresent`. Today it is `version`, `id` and `uiState`. There is no separate `root`: the id *is* the path.

```swift
public struct WorkspaceSnapshot: Codable, Sendable {
    public var version = 1
    public var id: WorkspaceID
    public var openTabs: [URL]                 // with the editor's tabs
    public var activeTab: URL?                 // with the editor's tabs
    public var agentSessions: [AgentSessionRef] // with AgentSessionsFeature
    public var uiState: [String: Data]   // keyed by PersistedWorkspaceUIState.persistenceKey
}
```

## Concurrency

- Swift 6 language mode everywhere. Zero concurrency warnings.
- `NonisolatedNonsendingByDefault` is enabled on every target. Without it a plain `nonisolated` async function runs on whichever actor called it, so `@concurrent` is what asks for the global executor — which is how the highlighter parses a megabyte without stopping the editor from redrawing.
- `Features`, components, `DesignSystem` and `AppFeature` use `.defaultIsolation(MainActor.self)`. `Core` and `Services` keep the nonisolated default; stores in Core are marked `@MainActor` explicitly.
- Prefer structured concurrency: `async`/`await`, task groups, and SwiftUI's `.task(id:)` for view-tied work so it cancels automatically.
- No new `DispatchQueue` usage and no completion-handler APIs in new code. The two that exist are at a C or AppKit boundary with no `async` equivalent (FSEvents needs a dispatch queue; the line-number ruler defers `needsDisplay` out of a layout pass) and carry a `// CONCURRENCY:` comment.
- Escape hatches (`@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency import`) require a `// CONCURRENCY:` comment on the same or preceding line explaining why it's safe.

## Rust

- The syntax highlighter lives in `packages/syntax-highlighter` and stays there. Don't move it, rename it, or restructure its crates as part of other work.
- It owns its build and binding generation. HerderKit consumes its output; HerderKit doesn't reach into its internals or duplicate its build steps. `just syntax` builds the XCFramework and copies it into `Packages/HerderKit/Vendor/`, so the `.binaryTarget` path stays inside the package and SwiftPM never depends on Cargo's output directory.
- **The bindings are hand-written**, not generated: a C header and a modulemap in `packages/syntax-highlighter/include/`, declaring module `HerderSyntaxFFI`. The header is the API. It is edited by hand, in step with `src/lib.rs`, and the two must not drift — `SyntaxTests` asserts the kind count matches.
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

## Agents and terminal

- PTY management lives in `Services/Process/`. The terminal emulator view lives in `Components/TerminalUI/`.
- `TerminalFeature` and `AgentSessionsFeature` both build on `TerminalUI`.
- Agent sessions belong to a `Workspace` (`AgentSessionStore`) and keep running while that workspace is in the background.

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
just bootstrap # syntax + project. Needed once in a fresh clone, and needs a Rust toolchain.
just syntax    # runs packages/syntax-highlighter's own build, then copies the XCFramework into Vendor/
just project   # xcodegen generate. Needed after changing Herder/ or UITests/, not HerderKit.
just build     # project + syntax, then xcodebuild
just test      # the Swift Testing suites, via xcodebuild
just dev       # build and run, with output in this terminal
just uitest    # the XCTest UI suite. Slow; launches the app.
just check     # scripts/check-boundaries.sh
```

`just test` goes through `xcodebuild test -scheme HerderKit-Package` rather than `swift test`, because PhosphorSwift ships its icons as an asset catalog without declaring it a resource, which only Xcode's build system bundles. `swift test` does not work here.

`build`, `test` and `bootstrap` all depend on `syntax`, because a stale static library links without complaint: the app would highlight with yesterday's grammars and nothing would say so.
