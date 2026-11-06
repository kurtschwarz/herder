import Foundation

/// The one writer of ``AppSnapshot``.
///
/// The repository list and the window index share that snapshot's key, and each
/// change to either reads the whole snapshot, edits its own part and writes it
/// back. Two of those running at once would each write back a snapshot missing
/// the other's edit, and what goes missing could be the list of bookmarks. So
/// every change goes through here, one after another.
@MainActor
public final class AppSnapshotStore {
    private let state: any StateStore

    /// The tail of the queue. Each change waits for the one before it.
    private var writes: Task<Void, any Error>?

    public init(state: any StateStore) {
        self.state = state
    }

    /// The snapshot as of every change queued so far, or an empty one when
    /// nothing is stored or what is stored cannot be read.
    public func read() async -> AppSnapshot {
        _ = try? await writes?.value
        return await state.loadIfReadable(AppSnapshot.self, forKey: AppSnapshot.persistenceKey) ?? AppSnapshot()
    }

    /// Lets `change` edit the stored snapshot and writes it back if anything
    /// came out different. Throws what the store said, to the caller whose
    /// change it was: an earlier change failing is that caller's to hear about,
    /// not this one's.
    public func update(_ change: @escaping @MainActor (inout AppSnapshot) -> Void) async throws {
        let previous = writes
        let task = Task { [state] in
            _ = try? await previous?.value
            var snapshot = await state.loadIfReadable(AppSnapshot.self, forKey: AppSnapshot.persistenceKey)
                ?? AppSnapshot()
            let before = snapshot
            change(&snapshot)
            guard snapshot != before else { return }
            try await state.save(snapshot, forKey: AppSnapshot.persistenceKey)
        }
        writes = task
        try await task.value
    }
}
