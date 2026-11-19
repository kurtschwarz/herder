#if DEBUG
import Core
import Foundation
import Synchronization

/// `DaemonClient` that reaches nothing. A test says what the daemon answers.
public final class StubDaemonClient: DaemonClient {
    public typealias Responder = @Sendable (Data) throws -> Data

    private struct State {
        var status: DaemonStatus
        var calls = 0
        var requests: [Data] = []
        var responder: Responder?
    }

    private let state: Mutex<State>

    public init(status: DaemonStatus = .connected(DaemonInfo(daemonVersion: "0.0.0", protocolVersion: DaemonWire.supported.upperBound, host: "local"))) {
        state = Mutex(State(status: status))
    }

    /// Every payload sent with ``request(_:)``, in order.
    public var requests: [Data] { state.withLock { $0.requests } }

    /// What the next requests answer with. Without one they throw.
    public func respond(with responder: @escaping Responder) {
        state.withLock { $0.responder = responder }
    }

    /// How often it was asked.
    public var calls: Int { state.withLock { $0.calls } }

    /// What the next connections answer.
    public func answer(_ status: DaemonStatus) {
        state.withLock { $0.status = status }
    }

    public func request(_ payload: Data) async throws -> Data {
        let responder = state.withLock { state in
            state.requests.append(payload)
            return state.responder
        }
        guard let responder else { throw StubDaemonClientError.unreachable }
        return try responder(payload)
    }

    public func connect() async -> DaemonStatus {
        state.withLock { state in
            state.calls += 1
            return state.status
        }
    }
}

public enum StubDaemonClientError: Error, Equatable {
    case unreachable
}
#endif
