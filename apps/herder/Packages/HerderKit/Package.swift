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

let package = Package(
    name: "HerderKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AppFeature", targets: ["AppFeature"]),
        .library(name: "Clients", targets: ["Clients"]),
        .library(name: "Storage", targets: ["Storage"]),
    ],
    dependencies: [
        .package(url: "https://github.com/phosphor-icons/swift", from: "2.1.0"),
    ],
    targets: [
        // Plain Sendable value types. Never imports SwiftUI.
        .target(name: "Models", swiftSettings: core),

        // Side effects behind protocols: disk, network, processes, clocks.
        .target(name: "Clients", dependencies: ["Models"], swiftSettings: core),

        // Fakes for the above. Separate target so they never link into the app.
        .target(name: "ClientsTestSupport", dependencies: ["Models", "Clients"], swiftSettings: core),

        // The one module that owns reference types: the SwiftData `@Model`
        // classes, their schema versions and the container.
        .target(name: "Storage", dependencies: ["Models", "Clients"], swiftSettings: ui),

        // The authoritative file and git state of a worktree, watched and kept
        // fresh. Above the clients and below the features, because more than
        // one feature reads it and features never import each other.
        .target(name: "Worktrees", dependencies: ["Models", "Clients"], swiftSettings: ui),

        // Syntax highlighting. The grammars, their queries and the table
        // matching a file to a language are all in the `herder-syntax` Rust
        // crate under `packages/syntax`; this is the Swift face of it.
        //
        // An XCFramework because that is the only shape a `.binaryTarget`
        // takes. It is a build artifact, not a checked-in one: `just bootstrap`
        // and `just build` in `apps/herder` produce it, and a fresh clone has
        // to run one of them before this package will resolve.
        .binaryTarget(name: "HerderSyntaxFFI", path: "Vendor/HerderSyntaxFFI.xcframework"),

        .target(name: "Syntax", dependencies: ["HerderSyntaxFFI"], swiftSettings: core),

        // Shared views, styles, tokens.
        .target(
            name: "DesignSystem",
            dependencies: [.product(name: "PhosphorSwift", package: "swift")],
            swiftSettings: ui
        ),

        // Root view and navigation. Add one target per feature alongside it under
        // `Sources/Features`, and depend on them from here: features never import
        // each other. Feature targets carry an explicit `path` because SwiftPM
        // otherwise looks for them directly under `Sources`.
        .target(
            name: "WorkspacesFeature",
            dependencies: [
                "Models", "Clients", "DesignSystem", "Storage",
                .product(name: "PhosphorSwift", package: "swift"),
            ],
            path: "Sources/Features/WorkspacesFeature",
            swiftSettings: ui
        ),

        .target(
            name: "ExplorerFeature",
            dependencies: [
                "Models", "Clients", "DesignSystem", "Worktrees",
                .product(name: "PhosphorSwift", package: "swift"),
            ],
            path: "Sources/Features/ExplorerFeature",
            swiftSettings: ui
        ),

        .target(
            name: "EditorFeature",
            dependencies: ["Models", "Clients", "DesignSystem", "Syntax", "Worktrees"],
            path: "Sources/Features/EditorFeature",
            swiftSettings: ui
        ),

        .target(
            name: "AppFeature",
            dependencies: [
                "Models", "Clients", "DesignSystem", "Storage", "Syntax", "Worktrees",
                "WorkspacesFeature", "ExplorerFeature", "EditorFeature",
            ],
            path: "Sources/Features/AppFeature",
            swiftSettings: ui
        ),

        .testTarget(
            name: "ModelsTests",
            dependencies: ["Models"],
            swiftSettings: core
        ),
        .testTarget(
            name: "ClientsTests",
            dependencies: ["Clients", "ClientsTestSupport"],
            swiftSettings: core
        ),
        .testTarget(
            name: "StorageTests",
            dependencies: ["Storage", "ClientsTestSupport"],
            swiftSettings: ui
        ),
        .testTarget(
            name: "SyntaxTests",
            dependencies: ["Syntax"],
            swiftSettings: core
        ),
        .testTarget(
            name: "WorktreesTests",
            dependencies: ["Worktrees", "Models", "Clients", "ClientsTestSupport"],
            swiftSettings: ui
        ),
        .testTarget(
            name: "WorkspacesFeatureTests",
            dependencies: ["WorkspacesFeature", "Clients", "ClientsTestSupport", "Storage"],
            path: "Tests/Features/WorkspacesFeatureTests",
            swiftSettings: ui
        ),
        .testTarget(
            name: "ExplorerFeatureTests",
            dependencies: ["ExplorerFeature", "Models", "Clients", "ClientsTestSupport", "Worktrees"],
            path: "Tests/Features/ExplorerFeatureTests",
            swiftSettings: ui
        ),
        .testTarget(
            name: "EditorFeatureTests",
            dependencies: ["EditorFeature", "Models", "Clients", "ClientsTestSupport", "Syntax", "Worktrees"],
            path: "Tests/Features/EditorFeatureTests",
            swiftSettings: ui
        ),
        .testTarget(
            name: "AppFeatureTests",
            dependencies: ["AppFeature", "ClientsTestSupport"],
            path: "Tests/Features/AppFeatureTests",
            swiftSettings: ui
        ),
    ]
)
