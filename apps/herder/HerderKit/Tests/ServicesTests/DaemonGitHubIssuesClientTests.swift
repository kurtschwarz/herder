import Core
import Foundation
import TestSupport
import Testing

@testable import Services

@Suite struct DaemonGitHubIssuesClientTests {
    let daemon = StubDaemonClient()

    func firstRequest() throws -> [String: Any] {
        let payload = try #require(daemon.requests.first)
        return try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
    }

    func respond(with body: @escaping @Sendable (Int) -> String) {
        daemon.respond { payload in
            let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
            return Data(body(object?["id"] as? Int ?? -1).utf8)
        }
    }

    @Test func aListIsAskedForByPathTabAndFreshnessAndReadBack() async throws {
        respond { id in
            #"{"type":"issue_response","id":\#(id),"result":{"repository":"o/r","status":{"state":"permission_missing"},"issues":[]}}"#
        }

        let list = try await DaemonGitHubIssuesClient(daemon: daemon).list(at: "/r", tab: .open, freshness: .fresh)

        #expect(list.status == .permissionMissing)
        #expect(list.repository == "o/r")
        let sent = try firstRequest()
        #expect(sent["type"] as? String == "issue_query")
        #expect(sent["path"] as? String == "/r")
        #expect(sent["tab"] as? String == "open")
        #expect(sent["freshness"] as? String == "fresh")
    }

    @Test func aDetailIsAskedForByNumberAndReadBack() async throws {
        respond { id in
            #"{"type":"issue_detail_response","id":\#(id),"result":{"status":{"state":"ok"}}}"#
        }

        let reply = try await DaemonGitHubIssuesClient(daemon: daemon).detail(at: "/r", number: 12)

        #expect(reply == GitHubIssueDetailReply(status: .ok))
        let sent = try firstRequest()
        #expect(sent["type"] as? String == "issue_detail")
        #expect(sent["number"] as? Int == 12)
    }

    @Test func eachRequestHasItsOwnId() async throws {
        respond { id in
            #"{"type":"issue_response","id":\#(id),"result":{"status":{"state":"ok"},"issues":[]}}"#
        }
        let client = DaemonGitHubIssuesClient(daemon: daemon)

        _ = try await client.list(at: "/r", tab: .open, freshness: .cached)
        _ = try await client.list(at: "/r", tab: .open, freshness: .fresh)

        let ids = daemon.requests.compactMap {
            (try? JSONSerialization.jsonObject(with: $0) as? [String: Any])?["id"] as? Int
        }
        #expect(Set(ids).count == 2)
    }

    @Test func aReplyThatIsNotTheAnswerThrows() async {
        respond { _ in #"{"type":"issue_response","id":999,"result":{"status":{"state":"ok"},"issues":[]}}"# }

        await #expect(throws: DaemonGitHubIssuesClient.Failure.unrecognisedReply) {
            try await DaemonGitHubIssuesClient(daemon: daemon).list(at: "/r", tab: .open, freshness: .fresh)
        }
    }

    @Test func aDaemonThatCannotBeReachedThrows() async {
        await #expect(throws: StubDaemonClientError.unreachable) {
            try await DaemonGitHubIssuesClient(daemon: daemon).detail(at: "/r", number: 1)
        }
    }
}
