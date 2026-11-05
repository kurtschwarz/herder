import Core
import Foundation
import SwiftData

/// Builds the SwiftData container for the workspace store.
///
/// One place that knows the schema, the migration plan and the store's location,
/// so the app target and the tests cannot drift apart on any of them.
///
/// CloudKit is off, and not as a decision deferred: a workspace carries a
/// security-scoped bookmark, which is specific to one Mac and one user account.
/// Synced rows would arrive somewhere they can never resolve.
public enum WorkspaceContainer {
    /// Backed by a file under Application Support. Used by the app.
    public static func live() throws -> ModelContainer {
        try container(for: ModelConfiguration(url: storeURL(), cloudKitDatabase: .none))
    }

    /// Backed by nothing, discarded with the test. Used by tests and previews.
    public static func inMemory() throws -> ModelContainer {
        try container(for: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    /// `~/Library/Application Support/Herder/Workspaces.store`, named explicitly
    /// rather than left to SwiftData's default so the file is findable.
    public static func storeURL() throws -> URL {
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Herder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "Workspaces.store")
    }

    private static func container(for configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: WorkspaceSchemaV2.self),
            migrationPlan: WorkspaceMigrationPlan.self,
            configurations: configuration
        )
    }
}
