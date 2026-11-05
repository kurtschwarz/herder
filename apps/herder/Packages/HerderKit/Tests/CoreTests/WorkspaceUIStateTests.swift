import Core
import Foundation
import TestSupport
import Testing

/// What a feature's UI state looks like: observable, default-constructible, and
/// knowing nothing about how it is stored.
@MainActor
private final class FileTreeUIState: WorkspaceUIState {
    var expanded: Set<String> = []
    init() {}
}

/// A second type, to check the bag keys on the type rather than handing out
/// whatever it made first.
@MainActor
private final class EditorUIState: WorkspaceUIState {
    var lastOpened: String?
    init() {}
}

@MainActor
private final class PersistedState: PersistedWorkspaceUIState {
    static let persistenceKey = "persisted"
    var value = ""
    init() {}

    func encode() throws -> Data { Data(value.utf8) }
    func restore(from data: Data) throws { value = String(decoding: data, as: UTF8.self) }
}

/// Encodes by throwing, to check one bad state does not take the snapshot with it.
@MainActor
private final class UnencodableState: PersistedWorkspaceUIState {
    static let persistenceKey = "unencodable"
    init() {}

    struct Nope: Error {}
    func encode() throws -> Data { throw Nope() }
    func restore(from data: Data) throws {}
}

@Suite @MainActor struct WorkspaceUIStateTests {
    /// A registry apiece, so two workspaces can be alive at once: one registry
    /// holds a single workspace and stops the rest on `select`.
    private func makeWorkspace(at path: String = "/code/api") async throws -> Workspace {
        let registry = WorkspaceRegistry(
            files: InMemoryFileClient(),
            git: StubGitClient(),
            watcher: StubFileWatcherClient(),
            clock: VirtualClockClient(),
            state: InMemoryStateStore()
        )
        return try #require(await registry.open(WorkspaceID(URL(filePath: path))))
    }

    @Test func askingTwiceGivesTheSameInstance() async throws {
        let workspace = try await makeWorkspace()

        let first = workspace.uiState(FileTreeUIState.self)
        first.expanded.insert("Sources")

        #expect(workspace.uiState(FileTreeUIState.self).expanded == ["Sources"])
        #expect(first === workspace.uiState(FileTreeUIState.self))
    }

    @Test func differentTypesGetDifferentInstances() async throws {
        let workspace = try await makeWorkspace()

        workspace.uiState(FileTreeUIState.self).expanded.insert("Sources")
        workspace.uiState(EditorUIState.self).lastOpened = "a.swift"

        #expect(workspace.uiState(FileTreeUIState.self).expanded == ["Sources"])
        #expect(workspace.uiState(EditorUIState.self).lastOpened == "a.swift")
    }

    /// The reason this exists at all: state on the workspace, not in `@State`,
    /// so switching away and back does not reset it.
    @Test func twoWorkspacesDoNotShareState() async throws {
        let one = try await makeWorkspace(at: "/code/one")
        let two = try await makeWorkspace(at: "/code/two")

        one.uiState(FileTreeUIState.self).expanded.insert("Sources")

        #expect(two.uiState(FileTreeUIState.self).expanded.isEmpty)
    }

    @Test func onlyPersistedStateIsEncoded() async throws {
        let workspace = try await makeWorkspace()
        workspace.uiState(FileTreeUIState.self).expanded.insert("Sources")
        workspace.uiState(PersistedState.self).value = "remembered"

        let encoded = workspace.snapshot.uiState

        #expect(encoded.keys.sorted() == ["persisted"])
        #expect(encoded["persisted"] == Data("remembered".utf8))
    }

    /// Nothing is written for a feature the user never opened: a default would
    /// claim it had been looked at.
    @Test func stateNeverAskedForIsNotEncoded() async throws {
        #expect(try await makeWorkspace().snapshot.uiState.isEmpty)
    }

    /// One pane's layout is not worth the rest of them.
    @Test func aStateThatCannotEncodeIsSkipped() async throws {
        let workspace = try await makeWorkspace()
        workspace.uiState(PersistedState.self).value = "kept"
        _ = workspace.uiState(UnencodableState.self)

        let encoded = workspace.snapshot.uiState

        #expect(encoded.keys.sorted() == ["persisted"])
    }

    /// The round trip that makes relaunch work: a feature asks for its state
    /// and finds what the last run wrote already in it.
    @Test func aFeatureGetsItsRestoredStateWhenItFirstAsks() async throws {
        let before = try await makeWorkspace()
        before.uiState(PersistedState.self).value = "remembered"

        let after = try await makeWorkspace()
        after.restore(from: before.snapshot)

        #expect(after.uiState(PersistedState.self).value == "remembered")
    }

    /// State for a pane the user never opened this session must survive being
    /// written back out, or closing a workspace would forget it.
    @Test func restoredStateNothingAsksForIsNotLost() async throws {
        let before = try await makeWorkspace()
        before.uiState(PersistedState.self).value = "remembered"

        let after = try await makeWorkspace()
        after.restore(from: before.snapshot)

        #expect(after.snapshot.uiState["persisted"] == Data("remembered".utf8))
    }

    @Test func snapshotCarriesTheWorkspaceIdentity() async throws {
        let workspace = try await makeWorkspace(at: "/code/api")
        #expect(workspace.snapshot.id == workspace.id)
        #expect(workspace.id.root.path == "/code/api")
    }
}
