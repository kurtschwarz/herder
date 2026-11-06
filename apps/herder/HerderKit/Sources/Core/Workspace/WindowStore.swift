import Foundation

/// Where windows' snapshots are kept, and which of them exist.
///
/// Each window's snapshot is its own key, so a window saving does not rewrite
/// another's. The index in ``AppSnapshot/windows`` records which exist and in
/// what order they were last used.
@MainActor
public final class WindowStore {
    /// How many snapshots are kept. A backstop: windows are removed when they
    /// are closed, and this bounds what a missed close can leave behind. The
    /// least recently used go first.
    public static let maxWindows = 20

    private let snapshots: AppSnapshotStore
    private let state: any StateStore

    public init(snapshots: AppSnapshotStore, state: any StateStore) {
        self.snapshots = snapshots
        self.state = state
    }

    /// The windows that have a snapshot, most recently used first.
    public func index() async -> [UUID] {
        await snapshots.read().windows
    }

    public func load(_ id: UUID) async -> WindowSnapshot? {
        await state.loadIfReadable(WindowSnapshot.self, forKey: WindowSnapshot.persistenceKey(for: id))
    }

    /// Writes the snapshot and makes its window the most recently used.
    public func save(_ snapshot: WindowSnapshot) async {
        // A window's layout is not worth failing anything over, and its next
        // change will try again.
        try? await state.save(snapshot, forKey: snapshot.persistenceKey)
        let id = snapshot.id
        try? await snapshots.update { app in
            app.windows.removeAll { $0 == id }
            app.windows.insert(id, at: 0)
        }
        for stale in await index().dropFirst(Self.maxWindows) {
            await remove(stale)
        }
    }

    /// Forgets a window that has been closed.
    ///
    /// Except the last one standing: closing every window leaves the next
    /// launch, or the next ⌘N, nothing to come back to, and a sidebar that
    /// forgot everything reads as data loss. The last window's snapshot stays
    /// until another window outlives it.
    public func discard(_ id: UUID) async {
        guard await index() != [id] else { return }
        await remove(id)
    }

    private func remove(_ id: UUID) async {
        try? await state.remove(forKey: WindowSnapshot.persistenceKey(for: id))
        try? await snapshots.update { app in app.windows.removeAll { $0 == id } }
    }
}
