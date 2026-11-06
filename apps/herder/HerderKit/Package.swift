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
        // Models, service protocols and workspace state.
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

        // libghostty-vt, the terminal emulation under `TerminalUI`. Built from
        // the commit pinned in `packages/ghostty-vt` by `just ghostty`, and
        // like the one above a build artifact a fresh clone has to make first.
        // Its API is not stable, so only `TerminalUI` may import it.
        .binaryTarget(name: "GhosttyVt", path: "Vendor/GhosttyVt.xcframework"),

        // Shared views, styles, tokens.
        // Depends on `Core` only for the environment keys that carry Core's
        // action types across the App/feature boundary: `Core` cannot declare
        // them itself because it may not import SwiftUI. No design token knows
        // anything about a workspace.
        .target(name: "DesignSystem", dependencies: ["Core", icons], swiftSettings: ui),

        // The terminal view: the emulator, the renderer and the input, over a
        // `PTYSession` from Core. A component rather than a feature because the
        // terminal panel and agent sessions both draw one. Depends on
        // `DesignSystem` for the colours and the one font, and on nothing that
        // knows what a workspace is.
        .target(
            name: "TerminalUI",
            dependencies: ["Core", "DesignSystem", "GhosttyVt"],
            path: "Sources/Components/TerminalUI",
            swiftSettings: ui
        ),

        // Feature targets carry an explicit `path` because SwiftPM otherwise
        // looks for them directly under `Sources`. Each one sees `Core`,
        // `DesignSystem` and `TestSupport` and no other feature; the concrete
        // services are `AppFeature`'s business alone.
        .target(
            name: "RepositoriesFeature",
            dependencies: ["Core", "DesignSystem", "TestSupport", icons],
            path: "Sources/Features/Repositories",
            swiftSettings: ui
        ),

        .target(
            name: "FileTreeFeature",
            dependencies: ["Core", "DesignSystem", "TestSupport", icons],
            path: "Sources/Features/FileTree",
            swiftSettings: ui
        ),

        .target(
            name: "EditorFeature",
            dependencies: ["Core", "DesignSystem", "TestSupport"],
            path: "Sources/Features/Editor",
            swiftSettings: ui
        ),

        .target(
            name: "TerminalFeature",
            dependencies: ["Core", "DesignSystem", "TestSupport", "TerminalUI", icons],
            path: "Sources/Features/Terminal",
            swiftSettings: ui
        ),

        // Composition root, not a feature: the one module that names concrete
        // service types, and so the one that may import `Services`. It lives
        // outside `Sources/Features/` because it is not one, and keeps the
        // `AppFeature` module name because `project.yml` names the product.
        .target(
            name: "AppFeature",
            dependencies: [
                "Core", "Services", "DesignSystem", "TestSupport",
                "RepositoriesFeature", "FileTreeFeature", "EditorFeature", "TerminalFeature",
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
            name: "RepositoriesFeatureTests",
            dependencies: ["RepositoriesFeature", "Core", "TestSupport"],
            path: "Tests/Features/RepositoriesFeatureTests",
            swiftSettings: ui
        ),
        .testTarget(
            name: "FileTreeFeatureTests",
            dependencies: ["FileTreeFeature", "Core", "TestSupport"],
            path: "Tests/Features/FileTreeFeatureTests",
            swiftSettings: ui
        ),
        .testTarget(
            // `Services` because the editor's tests exercise the real
            // tree-sitter engine: what colour a span gets is part of what the
            // pane promises, and a fake highlighter cannot check it.
            name: "EditorFeatureTests",
            dependencies: ["EditorFeature", "Core", "Services", "TestSupport"],
            path: "Tests/Features/EditorFeatureTests",
            swiftSettings: ui
        ),
        .testTarget(
            name: "TerminalFeatureTests",
            dependencies: ["TerminalFeature", "Core", "TestSupport"],
            path: "Tests/Features/TerminalFeatureTests",
            swiftSettings: ui
        ),
        .testTarget(
            name: "TerminalUITests",
            dependencies: ["TerminalUI", "Core", "DesignSystem", "TestSupport"],
            path: "Tests/Components/TerminalUITests",
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
