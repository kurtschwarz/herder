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
        var delay: Duration?
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

    /// Holds every answer back this long, so a test can see what a request in
    /// flight looks like.
    public func delay(_ duration: Duration?) {
        state.withLock { $0.delay = duration }
    }

    public func list(
        at path: String, tab: GitHubIssueTab, freshness: GitHubIssueFreshness
    ) async throws -> GitHubIssueList {
        let (result, delay) = state.withLock { state -> (Result<GitHubIssueList, StubGitHubIssuesError>?, Duration?) in
            state.calls.append(Call(path: path, tab: tab, freshness: freshness))
            return (state.lists[Self.key(tab, freshness)], state.delay)
        }
        if let delay { try await Task.sleep(for: delay) }
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
