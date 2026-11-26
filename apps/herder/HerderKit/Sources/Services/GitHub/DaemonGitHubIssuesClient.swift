import Core
import Foundation
import Synchronization

/// `GitHubIssuesClient` that asks herderd, which holds the token and makes the
/// requests. See ADR 0005.
public struct DaemonGitHubIssuesClient: GitHubIssuesClient {
    public enum Failure: Error, Equatable {
        case unrecognisedReply
    }

    private let daemon: any DaemonClient
    private let nextID = Counter()

    public init(daemon: any DaemonClient) {
        self.daemon = daemon
    }

    public func list(
        at path: String, tab: GitHubIssueTab, freshness: GitHubIssueFreshness
    ) async throws -> GitHubIssueList {
        let id = nextID.next()
        let reply = try await daemon.request(
            DaemonWire.issueQuery(id: id, path: path, tab: tab, freshness: freshness)
        )
        guard let list = DaemonWire.issueList(fromReply: reply, id: id) else { throw Failure.unrecognisedReply }
        return list
    }

    public func detail(at path: String, number: Int) async throws -> GitHubIssueDetailReply {
        let id = nextID.next()
        let reply = try await daemon.request(DaemonWire.issueDetail(id: id, path: path, number: number))
        guard let detail = DaemonWire.issueDetail(fromReply: reply, id: id) else { throw Failure.unrecognisedReply }
        return detail
    }
}

private final class Counter: Sendable {
    private let value = Mutex(0)

    func next() -> Int {
        value.withLock {
            $0 += 1
            return $0
        }
    }
}
