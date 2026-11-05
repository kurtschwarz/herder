import Core
import Foundation
import Testing

/// Snapshots are the only thing in the app whose shape has to survive a build
/// change, so what they do on the way in matters more than what they hold.
@Suite struct SnapshotTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - WorkspaceID

    @Test func workspaceIDEncodesAsItsPath() throws {
        let id = WorkspaceID(PathKey(canonical: "/code/api"))
        #expect(String(decoding: try encoder.encode(id), as: UTF8.self) == "\"\\/code\\/api\"")
    }

    @Test func workspaceIDSurvivesARoundTrip() throws {
        let id = WorkspaceID(PathKey(canonical: "/code/api"))
        #expect(try decoder.decode(WorkspaceID.self, from: try encoder.encode(id)) == id)
    }

    /// A workspace is its folder, so two ids for one path are one id.
    @Test func workspaceIDsForOnePathAreEqual() {
        #expect(WorkspaceID(PathKey(canonical: "/code/api")) == WorkspaceID(PathKey(canonical: "/code/api")))
        #expect(WorkspaceID(PathKey(canonical: "/code/api")) != WorkspaceID(PathKey(canonical: "/code/web")))
    }

    // MARK: - WorkspaceSnapshot

    @Test func workspaceSnapshotSurvivesARoundTrip() throws {
        let snapshot = WorkspaceSnapshot(
            id: WorkspaceID(PathKey(canonical: "/code/api")),
            uiState: ["filetree": Data("expanded".utf8)]
        )
        #expect(try decoder.decode(WorkspaceSnapshot.self, from: try encoder.encode(snapshot)) == snapshot)
    }

    /// The whole migration strategy: a field that did not exist when the state
    /// was written decodes to its default rather than failing the load.
    @Test func workspaceSnapshotMissingEverythingOptionalStillDecodes() throws {
        let json = Data(#"{"id":"/code/api"}"#.utf8)

        let snapshot = try decoder.decode(WorkspaceSnapshot.self, from: json)

        #expect(snapshot.id == WorkspaceID(PathKey(canonical: "/code/api")))
        #expect(snapshot.uiState.isEmpty)
        #expect(snapshot.version == 1)
    }

    /// The identity is the one field that cannot be defaulted: a snapshot that
    /// does not say which workspace it is cannot be restored into one.
    @Test func workspaceSnapshotWithoutAnIdentityIsRefused() {
        #expect(throws: (any Error).self) {
            try decoder.decode(WorkspaceSnapshot.self, from: Data("{}".utf8))
        }
    }

    @Test func eachWorkspaceGetsItsOwnKey() {
        let api = WorkspaceSnapshot(id: WorkspaceID(PathKey(canonical: "/code/api")))
        let web = WorkspaceSnapshot(id: WorkspaceID(PathKey(canonical: "/code/web")))

        #expect(api.persistenceKey != web.persistenceKey)
        #expect(api.persistenceKey == WorkspaceSnapshot.persistenceKey(for: api.id))
    }

    // MARK: - AppSnapshot

    @Test func appSnapshotSurvivesARoundTrip() throws {
        let snapshot = AppSnapshot(openWorkspaces: [
            WorkspaceID(PathKey(canonical: "/code/api")),
            WorkspaceID(PathKey(canonical: "/code/web")),
        ])
        #expect(try decoder.decode(AppSnapshot.self, from: try encoder.encode(snapshot)) == snapshot)
    }

    /// Reopening in a different order would shuffle the sidebar for no reason
    /// the user caused.
    @Test func appSnapshotKeepsTheOrderWorkspacesWereOpenedIn() throws {
        let ids = ["/code/web", "/code/api", "/code/tools"].map { WorkspaceID(PathKey(canonical: $0)) }

        let decoded = try decoder.decode(AppSnapshot.self, from: try encoder.encode(AppSnapshot(openWorkspaces: ids)))

        #expect(decoded.openWorkspaces == ids)
    }

    @Test func anEmptyAppSnapshotDecodes() throws {
        let snapshot = try decoder.decode(AppSnapshot.self, from: Data("{}".utf8))
        #expect(snapshot.openWorkspaces.isEmpty)
        #expect(snapshot.version == 1)
    }
}
