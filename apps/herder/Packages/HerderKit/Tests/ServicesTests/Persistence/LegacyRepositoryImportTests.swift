import Core
import Foundation
import Services
import SwiftData
import TestSupport
import Testing

/// Bringing the adopted repositories across from the SwiftData store.
///
/// This is the path the user's real data takes exactly once, and the rows carry
/// security-scoped bookmarks that cannot be regenerated, so it is tested
/// against the committed V1 fixture rather than against rows this build wrote.
@Suite @MainActor struct LegacyRepositoryImportTests {
    private func copyOfV1Fixture() throws -> URL {
        let fixture = try #require(
            Bundle.module.url(forResource: "Fixtures/v1/Workspaces", withExtension: "store"),
            "the V1 fixture store is missing from the test bundle"
        )
        let directory = URL.temporaryDirectory.appending(path: "herder-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "Workspaces.store")
        try FileManager.default.copyItem(at: fixture, to: url)
        return url
    }

    private func legacyContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: WorkspaceSchemaV2.self),
            migrationPlan: WorkspaceMigrationPlan.self,
            configurations: ModelConfiguration(url: try copyOfV1Fixture(), cloudKitDatabase: .none)
        )
    }

    @Test func theRowsComeAcrossInOrderWithEverythingOnThem() throws {
        let rows = LegacyRepositoryImport(container: try legacyContainer()).rows()

        #expect(rows.map(\.name) == ["herder", "api"])
        #expect(rows.map(\.path) == ["/code/herder", "/code/api"])
        #expect(rows.map(\.order) == [0, 1])
        // The part that cannot be regenerated.
        #expect(rows.first?.bookmark == Data("fixture-bookmark".utf8))
        // Identity is kept, so nothing downstream that keyed off it is orphaned.
        #expect(Set(rows.map(\.id)).count == 2)
    }

    @Test func anEmptyStoreImportsNothing() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkspaceSchemaV2.self),
            migrationPlan: WorkspaceMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        #expect(LegacyRepositoryImport(container: container).rows().isEmpty)
    }

    /// The whole point: after importing, the list is in `StateStore` and the
    /// bookmarks are intact.
    @Test func importedRowsLandInTheStateStoreWithTheirBookmarks() async throws {
        let bookmarks = InMemoryBookmarkClient()
        let state = InMemoryStateStore()
        let store = RepositoryStore(bookmarks: bookmarks, git: StubGitClient(), state: state)

        await store.adopt(LegacyRepositoryImport(container: try legacyContainer()).rows())

        #expect(store.repositories.map(\.name) == ["herder", "api"])
        let snapshot = try await state.load(AppSnapshot.self, forKey: AppSnapshot.persistenceKey)
        #expect(snapshot?.repositories.map(\.name) == ["herder", "api"])
        #expect(snapshot?.repositories.first?.bookmark == Data("fixture-bookmark".utf8))
    }

    /// A user who has deleted every repository since migrating must not have
    /// them all come back on the next launch.
    @Test func adoptingDoesNothingWhenTheListIsNotEmpty() async throws {
        let state = InMemoryStateStore()
        let git = StubGitClient()
        git.seed(URL(filePath: "/code/kept"), .mainWorkingTree)
        let store = RepositoryStore(bookmarks: InMemoryBookmarkClient(), git: git, state: state)
        try await store.add(url: URL(filePath: "/code/kept"))

        await store.adopt(LegacyRepositoryImport(container: try legacyContainer()).rows())

        #expect(store.repositories.map(\.name) == ["kept"])
    }
}
