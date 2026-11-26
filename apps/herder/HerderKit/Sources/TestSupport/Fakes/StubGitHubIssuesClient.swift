#if DEBUG
import Core
import Foundation
import Synchronization

/// `GitHubIssuesClient` that reaches nothing. A test says what herderd answers,
/// per tab and freshness, and sees what was asked.
public final class StubGitHubIssuesClient: GitHubIssuesClient {
    public struct Call: Equatable, Sendable {
        public var path: String
        public var tab: GitHubIssueTab
        public var freshness: GitHubIssueFreshness

        public init(path: String, tab: GitHubIssueTab, freshness: GitHubIssueFreshness) {
            self.path = path
            self.tab = tab
            self.freshness = freshness
        }
    }

    private struct State {
        var lists: [String: Result<GitHubIssueList, StubGitHubIssuesError>] = [:]
        var details: [Int: Result<GitHubIssueDetailReply, StubGitHubIssuesError>] = [:]
        var calls: [Call] = []
        var detailCalls: [Int] = []
        var held: Set<GitHubIssueFreshness> = []
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    public init() {}

    /// Every list request, in order.
    public var calls: [Call] { state.withLock { $0.calls } }

    /// The number of every detail request, in order.
    public var detailCalls: [Int] { state.withLock { $0.detailCalls } }

    /// What a list request answers with. Without one it throws.
    public func answer(
        _ list: GitHubIssueList, tab: GitHubIssueTab, freshness: GitHubIssueFreshness
    ) {
        state.withLock { $0.lists[Self.key(tab, freshness)] = .success(list) }
    }

    public func fail(tab: GitHubIssueTab, freshness: GitHubIssueFreshness) {
        state.withLock { $0.lists[Self.key(tab, freshness)] = .failure(.unreachable) }
    }

    /// What a detail request for `number` answers with. Without one it throws.
    public func answer(_ reply: GitHubIssueDetailReply, number: Int) {
        state.withLock { $0.details[number] = .success(reply) }
    }

    public func failDetail(number: Int) {
        state.withLock { $0.details[number] = .failure(.unreachable) }
    }

    /// Holds list requests of `freshness` back until ``release()``, so a test
    /// can see what a request in flight looks like.
    public func hold(_ freshness: GitHubIssueFreshness) {
        state.withLock { _ = $0.held.insert(freshness) }
    }

    /// Lets every held request answer, and stops holding.
    public func release() {
        let waiters = state.withLock { state in
            state.held = []
            defer { state.waiters = [] }
            return state.waiters
        }
        for waiter in waiters { waiter.resume() }
    }

    /// How many requests are being held.
    public var waiting: Int { state.withLock { $0.waiters.count } }

    public func list(
        at path: String, tab: GitHubIssueTab, freshness: GitHubIssueFreshness
    ) async throws -> GitHubIssueList {
        state.withLock { $0.calls.append(Call(path: path, tab: tab, freshness: freshness)) }
        await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
            let isHeld = state.withLock { state in
                guard state.held.contains(freshness) else { return false }
                state.waiters.append(waiter)
                return true
            }
            if !isHeld { waiter.resume() }
        }
        // Read after the hold, so a test may change the answer meanwhile.
        let result = state.withLock { $0.lists[Self.key(tab, freshness)] }
        guard let result else { throw StubGitHubIssuesError.unreachable }
        return try result.get()
    }

    public func detail(at path: String, number: Int) async throws -> GitHubIssueDetailReply {
        let result = state.withLock { state -> Result<GitHubIssueDetailReply, StubGitHubIssuesError>? in
            state.detailCalls.append(number)
            return state.details[number]
        }
        guard let result else { throw StubGitHubIssuesError.unreachable }
        return try result.get()
    }

    private static func key(_ tab: GitHubIssueTab, _ freshness: GitHubIssueFreshness) -> String {
        "\(tab.rawValue)/\(freshness.rawValue)"
    }
}

public enum StubGitHubIssuesError: Error, Equatable {
    case unreachable
}
#endif
