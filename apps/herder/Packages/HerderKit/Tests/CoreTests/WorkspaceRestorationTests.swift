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

    /// The registry writes a workspace's snapshot before it lets go of it, so
    /// coming back to a worktree finds what the user had opened in it.
    @Test func switchingAwayWritesTheSnapshot() async throws {
        let registry = makeRegistry()
        let workspace = try #require(await registry.select(api))
        workspace.uiState(PaneState.self).expanded = ["Sources"]

        await registry.select(web)

        let saved = try await state.load(
            WorkspaceSnapshot.self,
            forKey: WorkspaceSnapshot.persistenceKey(for: WorkspaceID(PathKey(api)))
        )
        #expect(saved?.uiState["pane"] != nil)
    }

    /// Coming back to a worktree in the same session.
    @Test func comingBackRestoresWhatWasOpen() async throws {
        let registry = makeRegistry()
        let first = try #require(await registry.select(api))
        first.uiState(PaneState.self).expanded = ["Sources", "Tests"]

        await registry.select(web)
        let again = try #require(await registry.select(api))

        #expect(again.uiState(PaneState.self).expanded == ["Sources", "Tests"])
    }

    /// And across a launch, which is the same thing through a second registry.
    @Test func aRelaunchRestoresWhatWasOpen() async throws {
        let registry = makeRegistry()
        let workspace = try #require(await registry.select(api))
        workspace.uiState(PaneState.self).expanded = ["Sources"]
        await registry.select(nil)

        let relaunched = makeRegistry()
        let restored = try #require(await relaunched.select(api))

        #expect(restored.uiState(PaneState.self).expanded == ["Sources"])
    }

    /// Two worktrees keep separate snapshots, under separate keys.
    @Test func eachWorktreeRemembersItsOwn() async throws {
        let registry = makeRegistry()
        let first = try #require(await registry.select(api))
        first.uiState(PaneState.self).expanded = ["Sources"]
        let second = try #require(await registry.select(web))
        second.uiState(PaneState.self).expanded = ["docs", "bin"]
        await registry.select(nil)

        let relaunched = makeRegistry()
        #expect(try #require(await relaunched.select(api)).uiState(PaneState.self).expanded == ["Sources"])
        #expect(try #require(await relaunched.select(web)).uiState(PaneState.self).expanded == ["docs", "bin"])
    }

    /// A workspace nothing has been opened in writes nothing, so a first visit
    /// does not leave a row behind for every folder the user glances at.
    @Test func aWorkspaceWithNothingToSayWritesAnEmptySnapshot() async throws {
        let registry = makeRegistry()
        _ = await registry.select(api)
        await registry.select(nil)

        let saved = try await state.load(
            WorkspaceSnapshot.self,
            forKey: WorkspaceSnapshot.persistenceKey(for: WorkspaceID(PathKey(api)))
        )
        #expect(saved?.uiState.isEmpty == true)
    }

    // MARK: - The debounce

    /// Quitting is a synchronous callback with nowhere to await, so the save
    /// cannot wait for it. It happens shortly after the change settles instead.
    @Test func changesAreWrittenShortlyAfterTheySettle() async throws {
        let registry = makeRegistry()
        let workspace = try #require(await registry.select(api))

        workspace.uiState(PaneState.self).expanded = ["Sources"]
        workspace.scheduleSnapshotSave()

        // The virtual clock returns from a sleep at once, so the debounce plays
        // out immediately; a few yields let the task that was waiting on it run.
        for _ in 0..<50 where await state.keys.isEmpty { await Task.yield() }

        #expect(await state.keys.contains(WorkspaceSnapshot.persistenceKey(for: WorkspaceID(PathKey(api)))))
        #expect(clock.sleeps.contains(Workspace.saveDebounce))
    }

    /// A folder opened ten times in a second is one write, not ten.
    @Test func severalChangesCollapseIntoOneWrite() async throws {
        let registry = makeRegistry()
        let workspace = try #require(await registry.select(api))

        for name in ["a", "b", "c", "d"] {
            workspace.uiState(PaneState.self).expanded.insert(name)
            workspace.scheduleSnapshotSave()
        }
        for _ in 0..<50 where await state.keys.isEmpty { await Task.yield() }

        // Whatever the count of sleeps asked for, only one save survived to
        // write, and it wrote the final state rather than an intermediate one.
        let saved = try await state.load(
            WorkspaceSnapshot.self,
            forKey: WorkspaceSnapshot.persistenceKey(for: WorkspaceID(PathKey(api)))
        )
        let decoded = try JSONDecoder().decode([String].self, from: try #require(saved?.uiState["pane"]))
        #expect(Set(decoded) == ["a", "b", "c", "d"])
    }
}
