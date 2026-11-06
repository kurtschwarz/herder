#if DEBUG
import Core
import Foundation
import Synchronization

/// `PTYClient` that starts nothing. Each `spawn` makes a ``StubPTYSession`` the
/// test drives by hand: it says what the process wrote, what is in the
/// foreground, and when it exits.
public final class StubPTYClient: PTYClient {
    private struct State {
        var specs: [PTYSpec] = []
        var sessions: [StubPTYSession] = []
        var failure: PTYClientError?
    }

    private let state = Mutex(State())

    public init() {}

    /// Every spec asked for, in order.
    public var specs: [PTYSpec] { state.withLock { $0.specs } }

    /// Every session made, in order.
    public var sessions: [StubPTYSession] { state.withLock { $0.sessions } }

    /// Makes the next `spawn` fail, and every one after, until set to `nil`.
    public func failSpawns(with error: PTYClientError?) {
        state.withLock { $0.failure = error }
    }

    public func spawn(_ spec: PTYSpec) async throws(PTYClientError) -> any PTYSession {
        let session = StubPTYSession(spec: spec)
        let failure = state.withLock { state -> PTYClientError? in
            state.specs.append(spec)
            if state.failure == nil { state.sessions.append(session) }
            return state.failure
        }
        if let failure { throw failure }
        return session
    }
}
#endif
