#if DEBUG
import Core
import Foundation
import Synchronization

/// Clock whose sleeps return at once but still move time forward by what they
/// asked for.
///
/// Enough to test a debounce and the ceiling that stops it starving, without a
/// test that waits: a deadline measured against `now` plays out exactly as it
/// would in real time, at full speed. Nothing here blocks, so no test has to
/// arrange for a sleeper to be in place before letting time pass, which is the
/// usual source of flakiness in a hand-driven clock.
public final class VirtualClockClient: ClockClient {
    private struct State {
        var now = ContinuousClock.now
        var sleeps: [Duration] = []
    }

    private let state = Mutex(State())

    public init() {}

    public var now: ContinuousClock.Instant {
        state.withLock { $0.now }
    }

    /// Every sleep asked for, in order, so a test can assert the policy rather
    /// than only its effect.
    public var sleeps: [Duration] {
        state.withLock { $0.sleeps }
    }

    public func sleep(for duration: Duration) async throws {
        state.withLock {
            $0.sleeps.append(duration)
            $0.now = $0.now.advanced(by: duration)
        }
        // Still a suspension point, so whatever was waiting on this task gets
        // its turn exactly as it would have.
        try Task.checkCancellation()
        await Task.yield()
    }
}
#endif
