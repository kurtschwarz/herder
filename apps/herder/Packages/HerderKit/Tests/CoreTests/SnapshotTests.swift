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
        let snapshot = AppSnapshot(windows: [UUID(), UUID()])
        #expect(try decoder.decode(AppSnapshot.self, from: try encoder.encode(snapshot)) == snapshot)
    }

    /// The order is the point of the index: it says which window was used last.
    @Test func appSnapshotKeepsTheOrderWindowsWereUsedIn() throws {
        let ids = [UUID(), UUID(), UUID()]

        let decoded = try decoder.decode(AppSnapshot.self, from: try encoder.encode(AppSnapshot(windows: ids)))

        #expect(decoded.windows == ids)
    }

    @Test func anEmptyAppSnapshotDecodes() throws {
        let snapshot = try decoder.decode(AppSnapshot.self, from: Data("{}".utf8))
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.repositories.isEmpty)
        #expect(snapshot.version == 1)
    }

    /// Written before windows had state of their own. The fields it carried are
    /// ignored rather than failing the load, which would lose the repositories
    /// beside them.
    @Test func anOlderAppSnapshotWithFieldsThatMovedStillDecodes() throws {
        let json = Data(#"{"openWorkspaces":["/code/api"],"lastActiveWorkspace":"/code/api"}"#.utf8)
        #expect(try decoder.decode(AppSnapshot.self, from: json).windows.isEmpty)
    }

    // MARK: - WindowSnapshot

    @Test func windowSnapshotSurvivesARoundTrip() throws {
        let snapshot = WindowSnapshot(
            id: UUID(),
            openWorkspaces: [WorkspaceID(PathKey(canonical: "/code/api")), WorkspaceID(PathKey(canonical: "/code/web"))],
            activeWorkspace: WorkspaceID(PathKey(canonical: "/code/web"))
        )
        #expect(try decoder.decode(WindowSnapshot.self, from: try encoder.encode(snapshot)) == snapshot)
    }

    @Test func windowSnapshotMissingEverythingOptionalStillDecodes() throws {
        let id = UUID()
        let snapshot = try decoder.decode(WindowSnapshot.self, from: Data(#"{"id":"\#(id.uuidString)"}"#.utf8))

        #expect(snapshot.id == id)
        #expect(snapshot.openWorkspaces.isEmpty)
        #expect(snapshot.activeWorkspace == nil)
    }

    @Test func windowSnapshotWithoutAnIdentityIsRefused() {
        #expect(throws: (any Error).self) {
            try decoder.decode(WindowSnapshot.self, from: Data("{}".utf8))
        }
    }

    @Test func eachWindowGetsItsOwnKey() {
        #expect(WindowSnapshot(id: UUID()).persistenceKey != WindowSnapshot(id: UUID()).persistenceKey)
    }

    @Test func aWindowWithNothingInItIsBlank() {
        #expect(WindowSnapshot(id: UUID()).isBlank)
        #expect(!WindowSnapshot(id: UUID(), activeWorkspace: WorkspaceID(PathKey(canonical: "/code/api"))).isBlank)
    }
}
