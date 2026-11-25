import Core
import Synchronization

/// What watches each external tab's folder, cancelled when it goes, so a
/// closed window's file watches stop with its editor.
///
/// A holder rather than a dictionary on ``EditorModel`` because the model is
/// main-actor isolated and cannot cancel anything from its `deinit`.
nonisolated final class ExternalWatches: Sendable {
    private let tasks = Mutex<[PathKey: Task<Void, Never>]>([:])

    func set(_ task: Task<Void, Never>?, for key: PathKey) {
        let old = tasks.withLock { tasks in
            defer { tasks[key] = task }
            return tasks[key]
        }
        old?.cancel()
    }

    func cancel(_ key: PathKey) {
        tasks.withLock { $0.removeValue(forKey: key) }?.cancel()
    }

    deinit {
        for task in tasks.withLock({ $0.values }) { task.cancel() }
    }
}
