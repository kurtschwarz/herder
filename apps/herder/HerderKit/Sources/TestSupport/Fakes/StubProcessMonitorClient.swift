#if DEBUG
import Core
import Foundation
import Synchronization

/// `ProcessMonitorClient` that reads nothing. A test says what the next samples
/// are; once they run out it keeps answering with the last.
public final class StubProcessMonitorClient: ProcessMonitorClient {
    private struct State {
        var queue: [ProcessSample] = []
        var last: ProcessSample
        var calls = 0
    }

    private let state: Mutex<State>

    public init(initial: ProcessSample = ProcessSample(
        root: 1, takenAt: Date(timeIntervalSince1970: 0), coreCount: 8, physicalMemory: 16 << 30, processes: []
    )) {
        state = Mutex(State(last: initial))
    }

    /// How often it was asked, which is how a test sees that nothing polls.
    public var calls: Int { state.withLock { $0.calls } }

    /// The samples to answer with next, in order.
    public func enqueue(_ samples: ProcessSample...) {
        state.withLock { $0.queue.append(contentsOf: samples) }
    }

    public func sample() async -> ProcessSample {
        state.withLock { state in
            state.calls += 1
            if !state.queue.isEmpty { state.last = state.queue.removeFirst() }
            return state.last
        }
    }
}
#endif
