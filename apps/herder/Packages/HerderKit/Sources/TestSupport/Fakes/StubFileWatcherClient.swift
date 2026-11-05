#if DEBUG
import Core
import Foundation
import Synchronization

/// `FileWatcherClient` the test pushes events into, so no test needs a real
/// file system or has to wait for one to settle.
///
/// This is what makes the storm guardrail a unit test: fire ten thousand
/// synthetic batches, then assert git was asked a bounded number of times.
public final class StubFileWatcherClient: FileWatcherClient {
    private struct State {
        var continuations: [AsyncStream<FileChangeBatch>.Continuation] = []
        var watched: [[URL]] = []
        var positions: [FileWatcherPosition?] = []
        var next: UInt64 = 1
    }

    private let state = Mutex(State())

    public init() {}

    /// The roots of every `watch` call so far, in order.
    public var watched: [[URL]] {
        state.withLock { $0.watched }
    }

    /// The position every `watch` call was asked to resume from, in order.
    public var resumedFrom: [FileWatcherPosition?] {
        state.withLock { $0.positions }
    }

    public var isWatching: Bool {
        state.withLock { !$0.continuations.isEmpty }
    }

    public func watch(_ roots: [URL], from position: FileWatcherPosition?) -> AsyncStream<FileChangeBatch> {
        AsyncStream { continuation in
            state.withLock {
                $0.watched.append(roots)
                $0.positions.append(position)
                $0.continuations.append(continuation)
            }
        }
    }

    /// Reports `folders` as changed, with a position one on from the last.
    public func change(_ folders: [URL]) {
        send(FileChangeBatch(folders: Set(folders.map(PathKey.init))))
    }

    /// Reports the watcher having dropped events.
    public func dropEvents() {
        send(FileChangeBatch(needsFullScan: true))
    }

    /// Reports `root` as having been moved or deleted.
    public func vanish(_ root: URL) {
        send(FileChangeBatch(vanishedRoots: [PathKey(root)]))
    }

    public func send(_ batch: FileChangeBatch) {
        let (continuations, position) = state.withLock {
            let position = $0.next
            $0.next += 1
            return ($0.continuations, position)
        }
        var batch = batch
        if batch.position.raw == 0 { batch.position = FileWatcherPosition(raw: position) }
        for continuation in continuations { continuation.yield(batch) }
    }

    /// Ends every stream, as a watcher does when its session is torn down.
    public func finish() {
        let continuations = state.withLock { state -> [AsyncStream<FileChangeBatch>.Continuation] in
            defer { state.continuations = [] }
            return state.continuations
        }
        for continuation in continuations { continuation.finish() }
    }
}
#endif
