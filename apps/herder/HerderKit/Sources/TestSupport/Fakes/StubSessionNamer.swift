#if DEBUG
import Core
import Foundation
import Synchronization

/// ``SessionNamer`` whose answer is set by the test: a name, a failure, or no
/// answer at all until cancelled, as a hung endpoint gives.
public final class StubSessionNamer: SessionNamer {
    public enum Answer: Sendable {
        case name(SessionName)
        case failure
        case hangs
    }

    public struct Failure: Error, Equatable {}

    private struct State {
        var answer: Answer
        var asked: [String] = []
        var configurations: [NamingConfiguration] = []
    }

    private let state: Mutex<State>

    public init(_ answer: Answer = .failure) {
        state = Mutex(State(answer: answer))
    }

    public func answer(_ answer: Answer) {
        state.withLock { $0.answer = answer }
    }

    /// Every prompt asked about, in order.
    public var prompts: [String] { state.withLock { $0.asked } }

    /// Every configuration asked with, in order.
    public var configurations: [NamingConfiguration] { state.withLock { $0.configurations } }

    public func name(for prompt: String, using configuration: NamingConfiguration) async throws -> SessionName {
        let answer = state.withLock {
            $0.asked.append(prompt)
            $0.configurations.append(configuration)
            return $0.answer
        }
        switch answer {
        case .name(let name): return name
        case .failure: throw Failure()
        case .hangs:
            try await Task.sleep(for: .seconds(3600))
            throw Failure()
        }
    }
}
#endif
