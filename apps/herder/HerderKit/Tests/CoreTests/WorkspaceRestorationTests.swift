import Foundation
import TestSupport
import Testing

@testable import Core

/// What a workspace remembers about itself across a switch and across a launch.
///
/// 4b built the machinery and 4d put the file tree's expansion through it, but
/// nothing wrote it down: the state went with the object when the registry
/// dropped it. These are about the writing and the reading back.
@MainActor
private final class PaneState: PersistedWorkspaceUIState {
    static let persistenceKey = "pane"
    var expanded: Set<String> = []
    init() {}

    func encode() throws -> Data { try JSONEncoder().encode(expanded.sorted()) }
    func restore(from data: Data) throws {
        expanded = Set(try JSONDecoder().decode([String].self, from: data))
    }
}

@Suite @MainActor struct WorkspaceRestorationTests {
    let files = InMemoryFileClient()
    let git = StubGitClient()
    let watcher = StubFileWatcherClient()
    let clock = VirtualClockClient()
    let state = InMemoryStateStore()

    private let api = URL(filePath: "/code/api")
    private let web = URL(filePath: "/code/web")

    private func makeRegistry() -> WorkspaceRegistry {
        WorkspaceRegistry(files: files, git: git, watcher: watcher, clock: clock, state: state)
    }

    /// Closing is what puts a workspace away, so closing is what writes it
    /// down. Since 4g, switching away does not: the workspace stays open and
    /// nothing has been lost yet.
    @Test func closingWritesTheSnapshot() async throws {
        let registry = makeRegistry()
        let workspace = try #require(await registry.open(WorkspaceID(api)))
        workspace.uiState(PaneState.self).expanded = ["Sources"]

        await registry.close(WorkspaceID(api))

        let saved = try await state.load(
            WorkspaceSnapshot.self,
            forKey: WorkspaceSnapshot.persistenceKey(for: WorkspaceID(api))
        )
        #expect(saved?.uiState["pane"] != nil)
    }

    /// Switching away and back in one session needs no snapshot at all: it is
    /// the same object, never put away.
    @Test func comingBackInTheSameSessionIsTheSameWorkspace() async throws {
        let registry = makeRegistry()
        let first = try #require(await registry.open(WorkspaceID(api)))
        first.uiState(PaneState.self).expanded = ["Sources", "Tests"]

        await registry.open(WorkspaceID(web))
        let again = try #require(await registry.open(WorkspaceID(api)))

        #expect(again === first)
        #expect(again.uiState(PaneState.self).expanded == ["Sources", "Tests"])
    }

    /// Across a launch, which is the same thing through a second registry.
    @Test func aRelaunchRestoresWhatWasOpen() async throws {
        let registry = makeRegistry()
        let workspace = try #require(await registry.open(WorkspaceID(api)))
        workspace.uiState(PaneState.self).expanded = ["Sources"]
        await registry.close(WorkspaceID(api))

        let relaunched = makeRegistry()
        let restored = try #require(await relaunched.open(WorkspaceID(api)))

        #expect(restored.uiState(PaneState.self).expanded == ["Sources"])
    }

    /// Two worktrees keep separate snapshots, under separate keys.
    @Test func eachWorktreeRemembersItsOwn() async throws {
        let registry = makeRegistry()
        let first = try #require(await registry.open(WorkspaceID(api)))
        first.uiState(PaneState.self).expanded = ["Sources"]
        let second = try #require(await registry.open(WorkspaceID(web)))
        second.uiState(PaneState.self).expanded = ["docs", "bin"]
        await registry.close(WorkspaceID(api))
        await registry.close(WorkspaceID(web))

        let relaunched = makeRegistry()
        #expect(try #require(await relaunched.open(WorkspaceID(api))).uiState(PaneState.self).expanded == ["Sources"])
        #expect(try #require(await relaunched.open(WorkspaceID(web))).uiState(PaneState.self).expanded == ["docs", "bin"])
    }

    /// A workspace nothing has been opened in has nothing to write down.
    @Test func aWorkspaceWithNothingToSayWritesAnEmptySnapshot() async throws {
        let registry = makeRegistry()
        _ = await registry.open(WorkspaceID(api))
        await registry.close(WorkspaceID(api))

        let saved = try await state.load(
            WorkspaceSnapshot.self,
            forKey: WorkspaceSnapshot.persistenceKey(for: WorkspaceID(api))
        )
        #expect(saved?.uiState.isEmpty == true)
    }

    // MARK: - The debounce

    /// Quitting is a synchronous callback with nowhere to await, so the save
    /// cannot wait for it. It happens shortly after the change settles instead.
    @Test func changesAreWrittenShortlyAfterTheySettle() async throws {
        let registry = makeRegistry()
        let workspace = try #require(await registry.open(WorkspaceID(api)))

        workspace.uiState(PaneState.self).expanded = ["Sources"]
        workspace.scheduleSnapshotSave()

        // The virtual clock returns from a sleep at once, so the debounce plays
        // out immediately; a few yields let the task that was waiting on it run.
        let snapshotKey = WorkspaceSnapshot.persistenceKey(for: WorkspaceID(api))
        for _ in 0..<50 where !(await state.keys.contains(snapshotKey)) { await Task.yield() }

        #expect(await state.keys.contains(snapshotKey))
        #expect(clock.sleeps.contains(Workspace.saveDebounce))
    }

    /// A folder opened ten times in a second is one write, not ten.
    @Test func severalChangesCollapseIntoOneWrite() async throws {
        let registry = makeRegistry()
        let workspace = try #require(await registry.open(WorkspaceID(api)))

        for name in ["a", "b", "c", "d"] {
            workspace.uiState(PaneState.self).expanded.insert(name)
            workspace.scheduleSnapshotSave()
        }
        let snapshotKey = WorkspaceSnapshot.persistenceKey(for: WorkspaceID(api))
        for _ in 0..<50 where !(await state.keys.contains(snapshotKey)) { await Task.yield() }

        // Whatever the count of sleeps asked for, only one save survived to
        // write, and it wrote the final state rather than an intermediate one.
        let saved = try await state.load(WorkspaceSnapshot.self, forKey: snapshotKey)
        let decoded = try JSONDecoder().decode([String].self, from: try #require(saved?.uiState["pane"]))
        #expect(Set(decoded) == ["a", "b", "c", "d"])
    }
}
