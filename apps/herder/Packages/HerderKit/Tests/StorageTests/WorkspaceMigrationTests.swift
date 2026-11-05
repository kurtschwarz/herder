import Core
import Foundation
import Storage
import SwiftData
import Testing

/// Opening a store that already exists on disk.
///
/// In-memory containers never exercise this: they are created at the current
/// version every time, so a schema change that strands the existing store looks
/// fine in every other test here. These are file-backed for that reason.
///
/// What they protect is the one thing in the app that cannot be rebuilt. A
/// `Repository` carries a security-scoped bookmark — the sandbox's standing
/// permission to reopen a folder — and regenerating one means asking the user to
/// find the folder again in an open panel. A migration that drops the table
/// costs them every folder they have ever added.
@Suite struct WorkspaceMigrationTests {
    /// A directory of its own per test: these suites run in parallel and a
    /// shared store path would have them opening each other's files.
    private func makeStoreURL() throws -> URL {
        let directory = URL.temporaryDirectory.appending(path: "herder-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "Workspaces.store")
    }

    private func container(
        _ schema: any VersionedSchema.Type,
        at url: URL,
        migrating: (any SchemaMigrationPlan.Type)? = nil
    ) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: schema),
            migrationPlan: migrating,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
    }

    /// Copies the committed V1 fixture somewhere writable and returns the copy.
    ///
    /// Never opened in place: opening it with the migration plan would migrate
    /// the fixture to V2 and it would stop being a V1 store.
    private func copyOfV1Fixture() throws -> URL {
        let fixture = try #require(
            Bundle.module.url(forResource: "Fixtures/v1/Workspaces", withExtension: "store"),
            "the V1 fixture store is missing from the test bundle"
        )
        let url = try makeStoreURL()
        try FileManager.default.copyItem(at: fixture, to: url)
        return url
    }

    /// The regression, against a store this build did not write.
    ///
    /// Building the "old" store from today's schema cannot catch a rename: both
    /// sides move together, so the store comes out describing whatever the code
    /// currently says and opens fine. Only a file written before the change has
    /// anything to say, which is why the fixture is committed.
    @Test func theStoreOnDiskOpensAtTheCurrentVersionWithItsRowsIntact() throws {
        let url = try copyOfV1Fixture()

        let current = try container(WorkspaceSchemaV2.self, at: url, migrating: WorkspaceMigrationPlan.self)
        let repositories = try ModelContext(current)
            .fetch(FetchDescriptor<Repository>(sortBy: [SortDescriptor(\.order)]))

        #expect(repositories.map(\.name) == ["herder", "api"])
        #expect(repositories.map(\.path) == ["/code/herder", "/code/api"])
        // The bookmark is the part that cannot be regenerated.
        #expect(repositories.first?.bookmark == Data("fixture-bookmark".utf8))
    }

    /// A store written at V1 and still at V1 must be recognised, not treated as
    /// a version the plan has never heard of. This is the exact failure the 4a
    /// rename caused: "Cannot use staged migration with an unknown model version".
    @Test func theStoreOnDiskIsARecognisedVersion() throws {
        let url = try copyOfV1Fixture()
        // Throws with an unknown model version if V1 no longer describes what
        // is in the file.
        _ = try container(WorkspaceSchemaV2.self, at: url, migrating: WorkspaceMigrationPlan.self)
    }

    /// A store already migrated to V2 keeps working, so the fixture's own
    /// migration is not a one-shot that breaks on the second launch.
    @Test func theMigratedStoreReopens() throws {
        let url = try copyOfV1Fixture()
        _ = try container(WorkspaceSchemaV2.self, at: url, migrating: WorkspaceMigrationPlan.self)

        let again = try container(WorkspaceSchemaV2.self, at: url, migrating: WorkspaceMigrationPlan.self)
        #expect(try ModelContext(again).fetch(FetchDescriptor<Repository>()).count == 2)
    }

    /// The entity name is the class name, and the store records it. This is what
    /// the renaming in 4a broke: a schema describing an entity the store has
    /// never heard of makes the whole store an unknown model version.
    @Test func theStoredEntityIsStillCalledWorkspace() throws {
        let url = try makeStoreURL()
        _ = try container(WorkspaceSchemaV2.self, at: url, migrating: WorkspaceMigrationPlan.self)

        let entities = Schema(versionedSchema: WorkspaceSchemaV2.self).entities.map(\.name).sorted()

        #expect(entities == ["StoredState", "Workspace"])
    }

    /// V1 and V2 have to describe the same entity for the stage to be
    /// lightweight. If they drift, the migration becomes a drop and a create.
    @Test func bothVersionsDescribeTheSameRepositoryEntity() {
        let v1 = Schema(versionedSchema: WorkspaceSchemaV1.self).entities
        let v2 = Schema(versionedSchema: WorkspaceSchemaV2.self).entities

        let repositoryInV1 = v1.first { $0.name == "Workspace" }
        let repositoryInV2 = v2.first { $0.name == "Workspace" }

        #expect(repositoryInV1 != nil)
        #expect(repositoryInV1 == repositoryInV2)
    }

    /// Opening the same store twice must not migrate twice or lose anything.
    @Test func reopeningAnAlreadyMigratedStoreIsAnoOp() throws {
        let url = try makeStoreURL()

        do {
            let first = try container(WorkspaceSchemaV2.self, at: url, migrating: WorkspaceMigrationPlan.self)
            let context = ModelContext(first)
            context.insert(Repository(name: "api", path: "/code/api", bookmark: Data(), order: 0))
            try context.save()
        }

        let second = try container(WorkspaceSchemaV2.self, at: url, migrating: WorkspaceMigrationPlan.self)
        #expect(try ModelContext(second).fetch(FetchDescriptor<Repository>()).count == 1)
    }

    /// App state and repositories share one store, so the V2 addition must not
    /// have given the repositories a new home.
    @Test func stateSavedAfterMigrationLandsBesideTheRepositories() async throws {
        let url = try makeStoreURL()

        do {
            let v1 = try container(WorkspaceSchemaV1.self, at: url)
            let context = ModelContext(v1)
            context.insert(Repository(name: "herder", path: "/code/herder", bookmark: Data(), order: 0))
            try context.save()
        }

        let current = try container(WorkspaceSchemaV2.self, at: url, migrating: WorkspaceMigrationPlan.self)
        let state = SwiftDataStateStore(container: current)
        try await state.save(AppSnapshot(openWorkspaces: [WorkspaceID(PathKey(canonical: "/code/herder"))]),
                             forKey: AppSnapshot.persistenceKey)

        #expect(try ModelContext(current).fetch(FetchDescriptor<Repository>()).count == 1)
        let loaded = try await state.load(AppSnapshot.self, forKey: AppSnapshot.persistenceKey)
        #expect(loaded?.openWorkspaces.count == 1)
    }
}
