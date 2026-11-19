#if DEBUG
import Core
import Foundation
import Synchronization

/// ``GitHubTokenVault`` in memory. A test can make it fail, and read what was
/// saved and deleted.
public final class InMemoryGitHubTokenVault: GitHubTokenVault {
    public struct Failure: Error, Equatable {
        public init() {}
    }

    private struct State {
        var tokens: GitHubTokens?
        var saved: [GitHubTokens] = []
        var deletes = 0
        var failsLoading = false
        var failsSaving = false
    }

    private let state: Mutex<State>

    public init(tokens: GitHubTokens? = nil) {
        state = Mutex(State(tokens: tokens))
    }

    /// What is stored now.
    public var tokens: GitHubTokens? { state.withLock { $0.tokens } }

    /// Everything saved, in order.
    public var saved: [GitHubTokens] { state.withLock { $0.saved } }

    public var deletes: Int { state.withLock { $0.deletes } }

    /// Puts `tokens` in the vault as though an earlier run had saved them,
    /// without counting as a save.
    public func seed(_ tokens: GitHubTokens?) { state.withLock { $0.tokens = tokens } }

    public func failLoading(_ fails: Bool = true) { state.withLock { $0.failsLoading = fails } }
    public func failSaving(_ fails: Bool = true) { state.withLock { $0.failsSaving = fails } }

    public func load() throws -> GitHubTokens? {
        try state.withLock { state in
            if state.failsLoading { throw Failure() }
            return state.tokens
        }
    }

    public func save(_ tokens: GitHubTokens) throws {
        try state.withLock { state in
            if state.failsSaving { throw Failure() }
            state.tokens = tokens
            state.saved.append(tokens)
        }
    }

    public func delete() throws {
        state.withLock { state in
            state.tokens = nil
            state.deletes += 1
        }
    }
}
#endif
