# Herder Architecture

This is the target architecture for Herder and the rulebook for anyone (human or agent) changing the code. If the code and this document disagree, assume the code is wrong. If you think the document is wrong, stop and ask Kurt rather than quietly diverging.

## Stack

- Swift 6 language mode, `swift-tools-version: 6.2`, macOS 26 and later
- SwiftUI for the app shell and panels; AppKit (`NSTextView` with TextKit 2) for the editor surface
- Rust for performance-sensitive work, starting with the syntax highlighter in `packages/syntax-highlighter`. That package stays where it is and keeps its own build and binding setup.
- Distributed with Developer ID signing and notarization. No App Sandbox, because Herder spawns processes and opens arbitrary folders.

## Layers

```
App target            composition root: windows, menus, builds real services
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

`RustBridge` is a role, not necessarily a target name. If `packages/syntax-highlighter` already ships its own Swift package, that package's product *is* the RustBridge: HerderKit depends on it directly, no separate `RustBridge` target is needed, and you substitute its module name wherever this document and `check-boundaries.sh` say `RustBridge`.

### Dependency rules

1. **Features** may import `Core`, `DesignSystem`, component modules (`*UI`), and `TestSupport` (for previews). Nothing else from HerderKit.
2. **Features never import other features.** Cross-feature coordination goes through `Workspace` in Core. Building blocks that several features need (for example the terminal emulator view) live in a component module such as `TerminalUI`.
3. **Services** may import `Core` and `RustBridge`.
4. **Core** imports only `Foundation` and `Observation`. Never SwiftUI, AppKit, SwiftData, or RustBridge.
5. **Only the App target** knows concrete service types. It constructs them in `AppEnvironment`.
6. **SwiftData**, while it exists, is imported only under `Services/Persistence/`.
7. **RustBridge types never leave Services.** Services translate FFI types to Core types at the boundary.

Rules 1, 2, 3 and 5 are enforced by target dependencies in `Package.swift`. Rules 4 and 6 (and the no-singletons rule below) are enforced by `scripts/check-boundaries.sh`, which must pass before any merge. Rule 7 is enforced in review.

## Repository layout

Herder lives in a monorepo. Everything Herder-specific lives under `apps/herder/`; the syntax highlighter is a shared package at the repo root.

**Path convention:** paths in these docs are relative to `apps/herder/`, except paths starting with `packages/`, which are relative to the repo root. Run commands from `apps/herder/`.

```
<repo root>/
├── apps/
│   ├── herder/
│   │   ├── Herder.xcodeproj             # thin: app target only
│   │   ├── App/                         # app target sources (real folder name from the survey)
│   │   │   ├── HerderApp.swift
│   │   │   ├── AppEnvironment.swift     # composition root: builds app-scoped services
│   │   │   ├── WindowModel.swift        # per-window state (active workspace)
│   │   │   ├── Commands/                # menu bar, keyboard shortcuts
│   │   │   └── Resources/               # assets, Info.plist, entitlements
│   │   │
│   │   ├── HerderKit/
│   │   │   ├── Package.swift
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
│   │   │   │   ├── RustBridge/          # only if syntax-highlighter has no Swift package of its own
│   │   │   │   ├── DesignSystem/        # Liquid Glass components, tokens, icons
│   │   │   │   ├── TestSupport/         # fakes for every service protocol (#if DEBUG)
│   │   │   │   ├── Components/
│   │   │   │   │   └── TerminalUI/      # shared building blocks, module <Name>UI
│   │   │   │   └── Features/
│   │   │   │       ├── Editor/          # module EditorFeature
│   │   │   │       ├── FileTree/        # module FileTreeFeature
│   │   │   │       ├── AgentSessions/   # module AgentSessionsFeature
│   │   │   │       ├── Terminal/        # module TerminalFeature
│   │   │   │       ├── Search/          # module SearchFeature
│   │   │   │       ├── CommandPalette/  # module CommandPaletteFeature
│   │   │   │       └── Settings/        # module SettingsFeature
│   │   │   └── Tests/
│   │   │       ├── CoreTests/
│   │   │       ├── ServicesTests/
│   │   │       └── <Name>FeatureTests/
│   │   │
│   │   ├── scripts/
│   │   │   └── check-boundaries.sh
│   │   ├── justfile
│   │   └── docs/
│   │       ├── ARCHITECTURE.md          # this file
│   │       └── REALIGNMENT.md
│   └── ...                              # other apps: not Herder's business
│
└── packages/
    ├── syntax-highlighter/              # Rust highlighter: stays here, owns its own build
    └── ...                              # other shared packages
```

HerderKit lives inside `apps/herder/` because nothing outside Herder uses it. If another app ever needs part of it, that part moves to `packages/` then, not before.

### Naming

- Feature folders are `Sources/Features/<Name>/`; the module is `<Name>Feature`. The suffix avoids module/type name collisions (a `FileTree` type inside a `FileTree` module confuses the compiler).
- Component folders are `Sources/Components/<Name>UI/`; the module is `<Name>UI`.
- One primary type per file, and the file is named after that type.

### Package.swift template

```swift
// swift-tools-version: 6.2
import PackageDescription

let mainActorByDefault: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

func feature(_ name: String, extraDeps: [Target.Dependency] = []) -> Target {
    .target(
        name: "\(name)Feature",
        dependencies: ["Core", "DesignSystem", "TestSupport"] + extraDeps,
        path: "Sources/Features/\(name)",
        swiftSettings: mainActorByDefault
    )
}

let package = Package(
    name: "HerderKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "HerderKit", targets: [
            "Core", "Services", "DesignSystem",
            "EditorFeature", "FileTreeFeature", "AgentSessionsFeature",
            "TerminalFeature", "SearchFeature", "CommandPaletteFeature", "SettingsFeature",
        ]),
    ],
    dependencies: [
        // packages/syntax-highlighter, when it ships its own Package.swift.
        .package(path: "../../../packages/syntax-highlighter"),
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "Services", dependencies: [
            "Core",
            // Use the real product name from the survey.
            .product(name: "SyntaxHighlighter", package: "syntax-highlighter"),
        ]),
        // If syntax-highlighter has no Package.swift, drop the package dependency above
        // and use a binaryTarget pointing at its build output plus a thin wrapper:
        //   .binaryTarget(name: "SyntaxHighlighterFFI", path: "../../../packages/syntax-highlighter/<path from survey>"),
        //   .target(name: "RustBridge", dependencies: ["SyntaxHighlighterFFI"]),
        // and make Services depend on "RustBridge" instead.
        .target(name: "DesignSystem", swiftSettings: mainActorByDefault),
        .target(name: "TestSupport", dependencies: ["Core"]),
        .target(name: "TerminalUI", dependencies: ["Core", "DesignSystem"],
                path: "Sources/Components/TerminalUI", swiftSettings: mainActorByDefault),

        feature("Editor"),
        feature("FileTree"),
        feature("Terminal", extraDeps: ["TerminalUI"]),
        feature("AgentSessions", extraDeps: ["TerminalUI"]),
        feature("Search"),
        feature("CommandPalette"),
        feature("Settings"),

        .testTarget(name: "CoreTests", dependencies: ["Core", "TestSupport"]),
        .testTarget(name: "ServicesTests", dependencies: ["Services", "TestSupport"]),
    ]
)
```

## State

### Hierarchy

```
WorkspaceRegistry          app-wide, one per process (Core)
 └── Workspace             one folder or git worktree (Core)
      ├── DocumentStore        open documents, tabs, dirty state
      ├── AgentSessionStore    agent sessions running in this worktree
      ├── git state            branch, status
      └── UI state bag         per-feature UI state (see below)

WindowModel                one per window (App)
 └── activeWorkspaceID     which workspace this window is showing
```

### Rules

- **`Workspace` is the single source of truth for one checkout.** If two places hold the same fact, one of them is a bug.
- **Switching workspaces or worktrees changes `WindowModel.activeWorkspaceID` and nothing else.** Never tear down documents, terminals, or agent sessions on a switch. Background worktrees keep running.
- **"Active" is per window, not global.** Multiple windows can show different workspaces.
- Opening and closing go through `WorkspaceRegistry.open(_:)` and `close(_:)`. Closing must prompt for dirty documents and running agents.
- Stores are `@MainActor @Observable public final class` with `public private(set)` state. Mutation happens only through methods (`workspace.documents.open(url)`, never `workspace.documents.tabs.append(...)`).
- Features receive their `Workspace` from the environment (`@Environment(Workspace.self)`). They never look up "the active workspace" themselves.
- Keep stores small and focused so Observation tracking stays precise. No god objects.

```swift
// App: root view resolves and injects
if let workspace = registry.workspace(for: window.activeWorkspaceID) {
    WorkspaceView()
        .environment(workspace)
}
```

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
    public func uiState<S: WorkspaceUIState>(_ type: S.Type = S.self) -> S
}

// FileTreeFeature
@Observable final class FileTreeUIState: WorkspaceUIState {
    var expanded: Set<URL> = []
    required init() {}
}
```

## Services

- Protocols live in `Core/Services/`. Implementations live in `Services/<Area>/`. Every protocol has a fake in `TestSupport/Fakes/`.
- Stateful services are `actor`s. Stateless ones are `Sendable` structs.
- Services never hold references to views or view models.
- Services report changes into the `Workspace` by calling its `@MainActor` methods. Views read from `Workspace` and feature models; they never call services for data. Feature models call services to perform actions.

### Scoping

| App-scoped (built once in `AppEnvironment`) | Workspace-scoped (built per workspace by `WorkspaceServicesFactory`) |
|---|---|
| Settings, keybindings, theme | File system + FSEvents watcher |
| `HighlightService` (Rust syntax engine) | Git |
| `StateStore` | Search |
| | Process / PTY |
| | Agent runner |

Workspace-scoped services are created when a workspace opens and torn down when it closes. Each one is bound to its workspace root, so there's never a question of which repo it's talking to.

### Dependency injection

`AppEnvironment` constructs services and passes them in through initializers or SwiftUI `@Entry` environment values. No `static let shared` singletons outside the App target.

## Persistence

- The source of truth for code is the disk and git. Herder persists only its own app state.
- `StateStore` (protocol in Core) loads and saves `Codable & Sendable` values by key.
- Live `@Observable` state converts to and from snapshot structs (`AppSnapshot`, `WorkspaceSnapshot`). Never make `@Observable` classes `Codable` directly; the macro's underscored backing storage leaks into the encoded keys.
- Snapshots carry a `version` field. New fields use `decodeIfPresent` with defaults. That's the whole migration strategy.
- Saves are debounced (about 1 second after changes settle) and also run on termination. Writes are atomic.
- Which workspace a window shows is stored with `@SceneStorage`.
- Agent transcripts are not stored by Herder. Store an `AgentSessionRef` (the Claude Code session ID plus any Herder label) so sessions can be resumed.
- Secrets go in the Keychain, never a file.
- Searchable indexes and history, when needed, use SQLite on the Rust side.

### Implementations

- **Transitional:** `SwiftDataStateStore` in `Services/Persistence/`, storing snapshot JSON blobs in a single `@Model`.
- **Target:** `FileStateStore` writing JSON:

```
~/Library/Application Support/Herder/
├── state.json                  # AppSnapshot: open workspaces, recents
└── workspaces/<id>.json        # WorkspaceSnapshot: tabs, UI state, agent session refs
```

```swift
public struct WorkspaceSnapshot: Codable, Sendable {
    public var version = 1
    public var id: WorkspaceID
    public var root: URL
    public var openTabs: [URL]
    public var activeTab: URL?
    public var agentSessions: [AgentSessionRef]
    public var uiState: [String: Data]   // keyed by PersistedWorkspaceUIState.persistenceKey
}
```

## Concurrency

- Swift 6 language mode everywhere. Zero concurrency warnings.
- `Features`, components and `DesignSystem` use `.defaultIsolation(MainActor.self)`. `Core`, `Services` and `RustBridge` keep the nonisolated default; stores in Core are marked `@MainActor` explicitly.
- Prefer structured concurrency: `async`/`await`, task groups, and SwiftUI's `.task(id:)` for view-tied work so it cancels automatically.
- No new `DispatchQueue` usage and no completion-handler APIs in new code.
- Escape hatches (`@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency import`) require a `// CONCURRENCY:` comment on the same or preceding line explaining why it's safe.

## Rust

- The syntax highlighter lives in `packages/syntax-highlighter` and stays there. Don't move it, rename it, or restructure its crates as part of other work.
- It owns its build and binding generation. HerderKit consumes its output; HerderKit doesn't reach into its internals or duplicate its build steps.
- Generated binding code is never hand-edited. Change the Rust side and regenerate.
- Changes to its public API (what Swift sees) are deliberate and get their own task.
- Swift touches it in exactly one place: the highlighting service in `Services/Highlighting/` (for example `RustHighlightService`), which converts its types to Core types.
- Keep the FFI API coarse: send edits, not whole documents; request highlights for the visible range; batch where possible.
- Any future Rust work (text ropes, file search) goes in its own package alongside it, as `packages/<name>`, following the same rules.
- **Offsets:** Core types use UTF-16 offsets to match `NSString` and TextKit. Tree-sitter works in UTF-8 bytes. Conversion happens in exactly one place: the service wrapping the FFI (for example `RustHighlightService`).

## Editor surface

- `NSTextView` with TextKit 2, wrapped in `NSViewRepresentable`. Not SwiftUI's `TextEditor`.
- Syntax highlighting is applied with `NSTextLayoutManager` rendering attributes, not text storage attributes. It's faster and keeps highlighting out of the undo stack.
- Text contents live in `NSTextStorage` and the Rust rope mirror. `Document` holds metadata (URL, language, dirty flag, buffer handle), not the text itself.

## Agents and terminal

- PTY management lives in `Services/Process/`. The terminal emulator view lives in `Components/TerminalUI/`.
- `TerminalFeature` and `AgentSessionsFeature` both build on `TerminalUI`.
- Agent sessions belong to a `Workspace` (`AgentSessionStore`) and keep running while that workspace is in the background.

## Testing and previews

- Unit tests use Swift Testing (`import Testing`).
- Core and Services have unit tests. Feature models are tested against fakes from `TestSupport`.
- Previews use fakes: `.environment(Workspace.preview())`.
- The syntax highlighter is tested with `cargo test` inside `packages/syntax-highlighter`.

## Code conventions

- Default to `internal`. A module's `public` surface is deliberate and small; a feature usually exposes one entry view.
- Views stay dumb: layout and bindings. Logic goes in the feature model, or in a small action type (`OpenFileAction`) when the model gets heavy.
- No singletons outside the App target.

## Commands

Run from `apps/herder/`.

```
just rust      # runs packages/syntax-highlighter's own build (bindings + library)
just test      # cargo test in packages/syntax-highlighter + swift test
just check     # scripts/check-boundaries.sh
```
