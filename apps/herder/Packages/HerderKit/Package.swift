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
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AppFeature", targets: ["AppFeature"]),
        .library(name: "Clients", targets: ["Clients"]),
    ],
    targets: [
        // Plain Sendable value types. Never imports SwiftUI.
        .target(name: "Models", swiftSettings: core),

        // Side effects behind protocols: disk, network, processes, clocks.
        .target(name: "Clients", dependencies: ["Models"], swiftSettings: core),

        // Fakes for the above. Separate target so they never link into the app.
        .target(name: "ClientsTestSupport", dependencies: ["Clients"], swiftSettings: core),

        // Shared views, styles, tokens.
        .target(name: "DesignSystem", swiftSettings: ui),

        // Root view and navigation. Add one target per feature alongside it, and
        // depend on them from here: features never import each other.
        .target(
            name: "AppFeature",
            dependencies: ["Models", "Clients", "DesignSystem"],
            swiftSettings: ui
        ),

        .testTarget(
            name: "ClientsTests",
            dependencies: ["Clients", "ClientsTestSupport"],
            swiftSettings: core
        ),
        .testTarget(
            name: "AppFeatureTests",
            dependencies: ["AppFeature", "ClientsTestSupport"],
            swiftSettings: ui
        ),
    ]
)
