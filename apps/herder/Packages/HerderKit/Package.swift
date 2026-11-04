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
        .target(name: "ClientsTestSupport", dependencies: ["Clients"], swiftSettings: core),

        // The one module that owns reference types: the SwiftData `@Model`
        // classes, their schema versions and the container.
        .target(name: "Storage", dependencies: ["Models", "Clients"], swiftSettings: ui),

        // Shared views, styles, tokens.
        .target(name: "DesignSystem", swiftSettings: ui),

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
            name: "AppFeature",
            dependencies: ["Models", "Clients", "DesignSystem", "Storage", "WorkspacesFeature"],
            path: "Sources/Features/AppFeature",
            swiftSettings: ui
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
            name: "WorkspacesFeatureTests",
            dependencies: ["WorkspacesFeature", "Clients", "ClientsTestSupport", "Storage"],
            path: "Tests/Features/WorkspacesFeatureTests",
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
