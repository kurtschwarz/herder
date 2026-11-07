#if DEBUG
import Core
import Foundation
import Synchronization

/// `CommandClient` whose answers are set by the test. A line it has no answer
/// for fails, as a missing program would.
public final class StubCommandClient: CommandClient {
    public struct Call: Equatable, Sendable {
        public var line: String
        public var directory: URL
    }

    private struct State {
        var outputs: [String: String] = [:]
        var calls: [Call] = []
    }

    private let state = Mutex(State())

    public init() {}

    /// What `line` prints from now on.
    public func answer(_ line: String, with output: String) {
        state.withLock { $0.outputs[line] = output }
    }

    /// Every command run, in order.
    public var calls: [Call] { state.withLock { $0.calls } }

    public func output(of line: String, in directory: URL) async -> String? {
        state.withLock { state in
            state.calls.append(Call(line: line, directory: directory))
            return state.outputs[line]
        }
    }
}
#endif
