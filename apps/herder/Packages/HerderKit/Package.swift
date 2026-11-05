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

let package = Package(
    name: "HerderKit",
    platforms: [.macOS(.v26)],
    products: [
        // One product. The app target links the composition root and nothing
        // else: `AppEnvironment` is what builds the live services, so there is
        // no longer anything for `@main` to inject.
        .library(name: "AppFeature", targets: ["AppFeature"]),
    ],
    dependencies: [
        .package(url: "https://github.com/phosphor-icons/swift", from: "2.1.0"),
    ],
    targets: [
        // Models, service protocols and — from Phase 4 — workspace state.
        // Imports only Foundation and Observation: never SwiftUI, AppKit,
        // SwiftData or the FFI. `scripts/check-boundaries.sh` enforces that.
        //
        // Nonisolated by default. The stores that arrive here in Phase 4 are
        // marked `@MainActor` explicitly rather than by target setting, because
        // everything else in this module must stay free of the main actor.
        .target(name: "Core", swiftSettings: core),

        // The implementations of Core's service protocols: disk, git, the file
        // watcher, the sandbox, the clock, and the syntax engine. The only
        // module that links the FFI.
        .target(name: "Services", dependencies: ["Core", "HerderSyntaxFFI"], swiftSettings: core),

        // Fakes for every service protocol, `#if DEBUG` so a release build
        // links an empty module. Features depend on this for their previews.
        .target(name: "TestSupport", dependencies: ["Core"], swiftSettings: core),

        // Syntax highlighting, over the `herder-syntax` Rust crate under
        // `packages/syntax-highlighter`. The grammars, their queries and the
        // table matching a file to a language all live there.
        //
        // An XCFramework because that is the only shape a `.binaryTarget`
        // takes. It is a build artifact, not a checked-in one: `just bootstrap`
        // and `just build` in `apps/herder` produce it, and a fresh clone has
        // to run one of them before this package will resolve.
        .binaryTarget(name: "HerderSyntaxFFI", path: "Vendor/HerderSyntaxFFI.xcframework"),

        // The one module that owns reference types: the SwiftData `@Model`
        // classes, their schema versions and the container. Becomes
        // `Services/Persistence/` in Phase 3.
        .target(name: "Storage", dependencies: ["Core"], swiftSettings: ui),

        // The authoritative file and git state of a worktree, watched and kept
        // fresh. Above the services and below the features, because more than
        // one feature reads it and features never import each other. Becomes
        // `Core/Workspace/` in Phase 4.
        .target(name: "Worktrees", dependencies: ["Core"], swiftSettings: ui),

        // Shared views, styles, tokens.
        .target(name: "DesignSystem", dependencies: [icons], swiftSettings: ui),

        // Feature targets carry an explicit `path` because SwiftPM otherwise
        // looks for them directly under `Sources`. Each one sees `Core`,
        // `DesignSystem` and `TestSupport` and no other feature; the concrete
        // services are `AppFeature`'s business alone.
        .target(
            name: "WorkspacesFeature",
            dependencies: ["Core", "DesignSystem", "TestSupport", "Storage", icons],
            path: "Sources/Features/WorkspacesFeature",
            swiftSettings: ui
        ),

        .target(
            name: "ExplorerFeature",
            dependencies: ["Core", "DesignSystem", "TestSupport", "Worktrees", icons],
            path: "Sources/Features/ExplorerFeature",
            swiftSettings: ui
        ),

        .target(
            name: "EditorFeature",
            dependencies: ["Core", "DesignSystem", "TestSupport", "Worktrees"],
            path: "Sources/Features/EditorFeature",
            swiftSettings: ui
        ),

        // Composition root, not a feature: the one module that names concrete
        // service types, and so the one that may import `Services`. It lives
        // outside `Sources/Features/` because it is not one, and keeps the
        // `AppFeature` module name because `project.yml` names the product.
        .target(
            name: "AppFeature",
            dependencies: [
                "Core", "Services", "DesignSystem", "TestSupport", "Storage", "Worktrees",
                "WorkspacesFeature", "ExplorerFeature", "EditorFeature",
            ],
            path: "Sources/App",
            swiftSettings: ui
        ),

        .testTarget(
            name: "CoreTests",
            dependencies: ["Core", "TestSupport"],
            swiftSettings: core
        ),
        .testTarget(
            name: "ServicesTests",
            dependencies: ["Services", "TestSupport"],
            swiftSettings: core
        ),
        .testTarget(
            name: "StorageTests",
            dependencies: ["Storage", "TestSupport"],
            swiftSettings: ui
        ),
        .testTarget(
            name: "WorktreesTests",
            dependencies: ["Worktrees", "Core", "TestSupport"],
            swiftSettings: ui
        ),
        .testTarget(
            name: "WorkspacesFeatureTests",
            dependencies: ["WorkspacesFeature", "Core", "TestSupport", "Storage"],
            path: "Tests/Features/WorkspacesFeatureTests",
            swiftSettings: ui
        ),
        .testTarget(
            name: "ExplorerFeatureTests",
            dependencies: ["ExplorerFeature", "Core", "TestSupport", "Worktrees"],
            path: "Tests/Features/ExplorerFeatureTests",
            swiftSettings: ui
        ),
        .testTarget(
            // `Services` because the editor's tests exercise the real
            // tree-sitter engine: what colour a span gets is part of what the
            // pane promises, and a fake highlighter cannot check it.
            name: "EditorFeatureTests",
            dependencies: ["EditorFeature", "Core", "Services", "TestSupport", "Worktrees"],
            path: "Tests/Features/EditorFeatureTests",
            swiftSettings: ui
        ),
        .testTarget(
            name: "AppFeatureTests",
            dependencies: ["AppFeature", "TestSupport"],
            path: "Tests/AppFeatureTests",
            swiftSettings: ui
        ),
    ]
)
