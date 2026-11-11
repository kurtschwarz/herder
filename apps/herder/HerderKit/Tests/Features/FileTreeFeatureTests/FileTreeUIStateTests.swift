import Core
import Foundation
import TestSupport
import Testing

@testable import FileTreeFeature

/// Expansion belongs to the worktree, not to the pane showing it.
///
/// It used to be a `Set` on `FileTreeModel`, cleared whenever the pane was
/// pointed somewhere else. That made "switch worktree and come back" close
/// everything the user had opened, and it is why the state now lives on the
/// `Workspace`.
@Suite @MainActor struct FileTreeUIStateTests {
    let files = InMemoryFileClient()
    let git = StubGitClient()
    let watcher = StubFileWatcherClient()
    let clock = VirtualClockClient()
    let state = InMemoryStateStore()
    let registry: WorkspaceRegistry
    let root = URL(filePath: "/code/api")
    let other = URL(filePath: "/code/web")

    init() {
        registry = WorkspaceRegistry(files: files, git: git, watcher: watcher, clock: clock, state: state)
    }

    private func dir(_ name: String, in parent: URL? = nil) -> DirectoryEntry {
        DirectoryEntry(url: (parent ?? root).appending(path: name), isDirectory: true)
    }

    @Test func expandingAFolderRecordsItOnTheWorkspace() async throws {
        files.seed(children: [dir("Sources")], of: root)
        files.seed(children: [], of: root.appending(path: "Sources"))
        let model = FileTreeModel(store: registry)

        await model.setRoot(root)
        await model.toggle(root.appending(path: "Sources"))

        let workspace = try #require(registry.state(for: root))
        #expect(workspace.uiState(FileTreeUIState.self).expanded == [PathKey(root.appending(path: "Sources"))])
    }

    /// The reason for the move: pointing the pane elsewhere must not throw away
    /// what the user opened in the worktree being left.
    @Test func leavingAWorktreeDoesNotCloseItsFolders() async throws {
        files.seed(children: [dir("Sources")], of: root)
        files.seed(children: [], of: root.appending(path: "Sources"))
        files.seed(children: [], of: other)
        let model = FileTreeModel(store: registry)

        await model.setRoot(root)
        await model.toggle(root.appending(path: "Sources"))
        // Held before the switch: the registry drops a workspace it is no
        // longer showing, which is what 4g changes. Holding it is what lets
        // this test be about the state rather than about the registry.
        let workspace = try #require(registry.state(for: root))

        await model.setRoot(other)

        #expect(workspace.uiState(FileTreeUIState.self).expanded == [PathKey(root.appending(path: "Sources"))])
    }

    /// Two worktrees' expansion must not run together, which is the thing a
    /// single set on the model could not express at all.
    @Test func twoWorktreesKeepSeparateExpansion() async throws {
        files.seed(children: [dir("Sources")], of: root)
        files.seed(children: [], of: root.appending(path: "Sources"))
        files.seed(children: [dir("Sources", in: other)], of: other)
        files.seed(children: [], of: other.appending(path: "Sources"))
        let model = FileTreeModel(store: registry)

        await model.setRoot(root)
        await model.toggle(root.appending(path: "Sources"))
        let first = try #require(registry.state(for: root))

        await model.setRoot(other)
        let second = try #require(registry.state(for: other))

        #expect(first.uiState(FileTreeUIState.self).expanded.count == 1)
        #expect(second.uiState(FileTreeUIState.self).expanded.isEmpty)
    }

    @Test func collapsingAllClosesOnlyTheWorktreeShown() async throws {
        files.seed(children: [dir("Sources")], of: root)
        files.seed(children: [], of: root.appending(path: "Sources"))
        let model = FileTreeModel(store: registry)

        await model.setRoot(root)
        await model.toggle(root.appending(path: "Sources"))
        model.collapseAll()

        let workspace = try #require(registry.state(for: root))
        #expect(workspace.uiState(FileTreeUIState.self).expanded.isEmpty)
    }

    /// With no worktree there is nothing for a path to be relative to, so
    /// expansion has nowhere to go and must not crash trying.
    @Test func expandingWithNoWorktreeIsHarmless() async {
        let model = FileTreeModel(store: registry)
        await model.toggle(root.appending(path: "Sources"))
        #expect(!model.canCollapse)
    }

    // MARK: - Persistence

    @Test func expansionSurvivesAnEncodeAndRestore() throws {
        let state = FileTreeUIState()
        state.expanded = [PathKey(canonical: "/code/api/Sources"), PathKey(canonical: "/code/api/Tests")]

        let restored = FileTreeUIState()
        try restored.restore(from: try state.encode())

        #expect(restored.expanded == state.expanded)
    }

    /// What the whole of 4b's machinery is for: the feature asks for its state
    /// and finds the last run's expansion already in it.
    @Test func aRestoredWorkspaceHandsExpansionBackOnFirstAsk() async throws {
        files.seed(children: [], of: root)
        let before = try #require(await registry.open(WorkspaceID(root)))
        before.uiState(FileTreeUIState.self).expanded = [PathKey(canonical: "/code/api/Sources")]

        let fresh = WorkspaceRegistry(files: files, git: git, watcher: watcher, clock: clock, state: state)
        let after = try #require(await fresh.open(WorkspaceID(root)))
        after.restore(from: before.snapshot)

        #expect(after.uiState(FileTreeUIState.self).expanded == [PathKey(canonical: "/code/api/Sources")])
    }

    private func restoredRegistry(expanded: Set<PathKey>) async throws -> WorkspaceRegistry {
        let before = try #require(await registry.open(WorkspaceID(root)))
        before.uiState(FileTreeUIState.self).expanded = expanded
        let snapshot = before.snapshot
        let fresh = WorkspaceRegistry(files: files, git: git, watcher: watcher, clock: clock, state: state)
        let after = try #require(await fresh.open(WorkspaceID(root)))
        after.restore(from: snapshot)
        return fresh
    }

    // MARK: - Restored folders

    /// The bug: a restored folder drew open with no listing, so the first click
    /// closed it and only the second read it.
    @Test func aRestoredOpenFolderShowsItsChildrenAndOneToggleClosesIt() async throws {
        let sources = dir("Sources")
        let nested = dir("Nested", in: sources.url)
        files.seed(children: [sources], of: root)
        files.seed(children: [nested], of: sources.url)
        files.seed(children: [DirectoryEntry(url: nested.url.appending(path: "A.swift"), isDirectory: false)], of: nested.url)
        let fresh = try await restoredRegistry(expanded: [PathKey(sources.url), PathKey(nested.url)])
        let model = FileTreeModel(store: fresh)

        await model.setRoot(root)

        #expect(model.isExpanded(sources.url))
        #expect(model.rows.map(\.depth) == [0, 1, 2])

        await model.toggle(nested.url)
        #expect(!model.isExpanded(nested.url))
        #expect(model.rows.count == 2)
    }

    @Test func aRestoredFolderThatNoLongerExistsIsSkippedSilently() async throws {
        files.seed(children: [dir("Sources")], of: root)
        files.seed(children: [], of: root.appending(path: "Sources"))
        let gone = root.appending(path: "Gone")
        let fresh = try await restoredRegistry(expanded: [PathKey(root.appending(path: "Sources")), PathKey(gone)])
        let model = FileTreeModel(store: fresh)

        await model.setRoot(root)

        #expect(model.listing(of: gone) == nil)
        #expect(!model.rows.contains { $0.kind == .unreadable })
    }
}
