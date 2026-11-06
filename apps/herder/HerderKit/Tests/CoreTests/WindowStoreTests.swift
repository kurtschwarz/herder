import Foundation
import TestSupport
import Testing

@testable import Core

/// Which windows have state, and which was used last.
@Suite @MainActor struct WindowStoreTests {
    let state = InMemoryStateStore()
    let store: WindowStore

    private let api = WorkspaceID(PathKey(canonical: "/code/api"))

    init() {
        store = WindowStore(snapshots: AppSnapshotStore(state: state), state: state)
    }

    private func window(_ id: UUID = UUID()) -> WindowSnapshot {
        WindowSnapshot(id: id, openWorkspaces: [api], activeWorkspace: api)
    }

    @Test func aSavedWindowComesBack() async throws {
        let saved = window()
        await store.save(saved)

        #expect(await store.load(saved.id) == saved)
    }

    @Test func aWindowNeverSavedIsNotThere() async {
        #expect(await store.load(UUID()) == nil)
    }

    @Test func theMostRecentlySavedIsFirst() async {
        let (older, newer) = (window(), window())
        await store.save(older)
        await store.save(newer)

        #expect(await store.index() == [newer.id, older.id])
    }

    @Test func savingAgainMovesItToTheFront() async {
        let (older, newer) = (window(), window())
        await store.save(older)
        await store.save(newer)
        await store.save(older)

        #expect(await store.index() == [older.id, newer.id])
    }

    @Test func discardingForgetsTheWindow() async {
        let (kept, closed) = (window(), window())
        await store.save(kept)
        await store.save(closed)

        await store.discard(closed.id)

        #expect(await store.load(closed.id) == nil)
        #expect(await store.index() == [kept.id])
    }

    /// Closing every window must leave something to come back to.
    @Test func theLastWindowIsKeptWhenItCloses() async {
        let only = window()
        await store.save(only)

        await store.discard(only.id)

        #expect(await store.load(only.id) == only)
        #expect(await store.index() == [only.id])
    }

    @Test func discardingSomethingNeverSavedIsHarmless() async {
        let kept = window()
        await store.save(kept)

        await store.discard(UUID())

        #expect(await store.index() == [kept.id])
    }

    /// The backstop for a close that was missed.
    @Test func beyondTheCapTheLeastRecentlyUsedGoFirst() async {
        let all = (0..<(WindowStore.maxWindows + 2)).map { _ in window() }
        for snapshot in all { await store.save(snapshot) }

        let index = await store.index()

        #expect(index.count == WindowStore.maxWindows)
        #expect(index.first == all.last?.id)
        #expect(await store.load(all[0].id) == nil)
        #expect(await store.load(all[1].id) == nil)
    }

    /// Windows and repositories share a file, so neither may write the other
    /// away.
    @Test func theIndexKeepsTheRepositories() async throws {
        let snapshots = AppSnapshotStore(state: state)
        let windows = WindowStore(snapshots: snapshots, state: state)
        let repository = Repository(name: "api", path: "/code/api", bookmark: Data([1]))
        try await snapshots.update { $0.repositories = [repository] }

        await windows.save(window())

        #expect(await snapshots.read().repositories.map(\.name) == ["api"])
    }

    /// Several edits at once each read the snapshot and write it whole. They
    /// are queued, so none loses another's field.
    @Test func concurrentEditsAllLand() async throws {
        let snapshots = AppSnapshotStore(state: state)
        let ids = (0..<8).map { _ in UUID() }

        let edits = ids.map { id in
            Task { try? await snapshots.update { $0.windows.append(id) } }
        }
        for edit in edits { await edit.value }

        #expect(Set(await snapshots.read().windows) == Set(ids))
    }
}
