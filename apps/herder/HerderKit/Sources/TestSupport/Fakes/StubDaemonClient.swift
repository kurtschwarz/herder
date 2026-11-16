#if DEBUG
import Core
import Synchronization

/// `DaemonClient` that reaches nothing. A test says what the daemon answers.
public final class StubDaemonClient: DaemonClient {
    private let state: Mutex<(status: DaemonStatus, calls: Int)>

    public init(status: DaemonStatus = .connected(DaemonInfo(daemonVersion: "0.0.0", protocolVersion: 1, host: "local"))) {
        state = Mutex((status, 0))
    }

    /// How often it was asked.
    public var calls: Int { state.withLock { $0.calls } }

    /// What the next connections answer.
    public func answer(_ status: DaemonStatus) {
        state.withLock { $0.status = status }
    }

    public func connect() async -> DaemonStatus {
        state.withLock { state in
            state.calls += 1
            return state.status
        }
    }
}
#endif
