import Foundation
import Testing

@testable import Core

/// The Swift half of the protocol in `packages/herderd/src/protocol.rs`.
@Suite struct DaemonWireTests {
    private func json(_ text: String) -> Data { Data(text.utf8) }

    @Test func aFrameIsABigEndianLengthThenThePayload() {
        let framed = DaemonWire.frame(Data([1, 2, 3]))

        #expect(Array(framed) == [0, 0, 0, 3, 1, 2, 3])
    }

    @Test func readsALengthFromAHeader() {
        #expect(DaemonWire.payloadLength(header: Data([0, 0, 1, 0])) == 256)
        #expect(DaemonWire.payloadLength(header: Data([0, 0])) == nil)
    }

    @Test func refusesAHeaderAnnouncingMoreThanAFrameMayCarry() {
        #expect(DaemonWire.payloadLength(header: Data([0xFF, 0xFF, 0xFF, 0xFF])) == nil)
    }

    @Test func helloIsFramedJSONNamingTheVersionsAndTheClient() throws {
        let hello = DaemonWire.hello(client: "Herder 1.0")
        let length = try #require(DaemonWire.payloadLength(header: hello.prefix(DaemonWire.headerSize)))
        let body = hello.dropFirst(DaemonWire.headerSize)

        #expect(body.count == length)
        #expect(String(decoding: body, as: UTF8.self)
            == #"{"client":"Herder 1.0","max_protocol":2,"min_protocol":2,"type":"hello"}"#)
    }

    @Test func aWelcomeIsConnected() {
        let status = DaemonWire.status(fromReply: json(
            #"{"type":"welcome","protocol":2,"daemon_version":"0.1.0","host":"local"}"#
        ))

        #expect(status == .connected(DaemonInfo(daemonVersion: "0.1.0", protocolVersion: 2, host: "local")))
    }

    @Test func anIncompatibleReplyKeepsBothRangesToShow() {
        let status = DaemonWire.status(fromReply: json(
            #"{"type":"incompatible","min_protocol":4,"max_protocol":6,"daemon_version":"2.0.0"}"#
        ))

        #expect(status == .incompatible(daemonVersion: "2.0.0", supports: 4...6, app: DaemonWire.supported))
    }

    @Test func aWelcomeToAVersionTheAppDoesNotSpeakIsNotConnected() {
        let status = DaemonWire.status(fromReply: json(
            #"{"type":"welcome","protocol":9,"daemon_version":"2.0.0","host":"local"}"#
        ))

        guard case .unavailable = status else {
            Issue.record("expected unavailable, got \(status)")
            return
        }
    }

    @Test(arguments: [
        "not json",
        #"{"type":"welcome"}"#,
        #"{"type":"mystery","daemon_version":"1"}"#,
        #"{"type":"incompatible","min_protocol":6,"max_protocol":4,"daemon_version":"1"}"#,
    ])
    func anythingElseIsUnavailable(reply: String) {
        guard case .unavailable = DaemonWire.status(fromReply: json(reply)) else {
            Issue.record("expected unavailable for \(reply)")
            return
        }
    }

    // MARK: - Git

    @Test func aGitRequestIsOneFlatObject() {
        let payload = DaemonWire.gitRequest(id: 7, op: "repository_kind", arguments: ["path": "/r"])

        #expect(String(decoding: payload, as: UTF8.self)
            == #"{"id":7,"op":"repository_kind","path":"/r","type":"git_request"}"#)
    }

    @Test func aGitResultIsTheResultOfTheMatchingResponse() throws {
        let result = try DaemonWire.gitResult(
            fromReply: json(#"{"type":"git_response","id":7,"result":{"kind":"bare"}}"#), id: 7
        )

        #expect(result["kind"] as? String == "bare")
    }

    @Test func aGitErrorIsWhatTheDaemonSaid() {
        #expect(throws: GitClientError.commandFailed("no")) {
            try DaemonWire.gitResult(
                fromReply: json(#"{"type":"git_response","id":7,"error":{"code":"failed","message":"no"}}"#), id: 7
            )
        }
    }

    @Test(arguments: [
        "not json",
        #"{"type":"git_response","id":8,"result":{}}"#,
        #"{"type":"welcome","id":7}"#,
        #"{"type":"git_response","id":7}"#,
    ])
    func aReplyThatIsNotTheAnswerIsAFailure(reply: String) {
        #expect(throws: GitClientError.self) {
            try DaemonWire.gitResult(fromReply: json(reply), id: 7)
        }
    }

    @Test func repositoryKindsReadBack() {
        #expect(DaemonWire.repositoryKind(fromResult: ["kind": "main_working_tree"]) == .mainWorkingTree)
        #expect(DaemonWire.repositoryKind(fromResult: ["kind": "bare"]) == .bare)
        #expect(DaemonWire.repositoryKind(fromResult: ["kind": "not_a_repository"]) == .notARepository)
        #expect(DaemonWire.repositoryKind(fromResult: ["kind": "linked_worktree", "main_repository": "/r"])
            == .linkedWorktree(mainRepository: URL(filePath: "/r", directoryHint: .isDirectory).resolvingSymlinksInPath()))
        #expect(DaemonWire.repositoryKind(fromResult: ["kind": "linked_worktree"]) == nil)
        #expect(DaemonWire.repositoryKind(fromResult: ["kind": "mystery"]) == nil)
    }

    @Test func worktreesReadBackWithTheirCheckoutAndActivity() throws {
        let worktrees = try #require(DaemonWire.worktrees(fromResult: [
            "worktrees": [
                ["host": "local", "path": "/r", "checkout": ["type": "branch", "name": "main"],
                 "is_main_working_tree": true, "last_activity": 100.0],
                ["host": "local", "path": "/r-d", "checkout": ["type": "detached", "sha": "abc1234"],
                 "is_main_working_tree": false],
            ],
        ]))

        #expect(worktrees.map(\.checkout) == [.branch("main"), .detached(sha: "abc1234")])
        #expect(worktrees.map(\.isMainWorkingTree) == [true, false])
        #expect(worktrees[0].lastActivity == Date(timeIntervalSince1970: 100))
        #expect(worktrees[1].lastActivity == nil)
    }

    @Test func aWorktreeRecordMissingAFieldIsNotAnAnswer() {
        #expect(DaemonWire.worktrees(fromResult: ["worktrees": [["path": "/r"]]]) == nil)
        #expect(DaemonWire.worktrees(fromResult: [:]) == nil)
    }

    @Test func gitDirectoryAndCheckoutKeepNullApartFromAMissingAnswer() {
        #expect(DaemonWire.gitDirectory(fromResult: ["path": NSNull()]) == .some(nil))
        #expect(DaemonWire.gitDirectory(fromResult: [:]) == nil)
        #expect(DaemonWire.checkout(fromResult: ["checkout": NSNull()]) == .some(nil))
        #expect(DaemonWire.checkout(fromResult: ["checkout": ["type": "branch", "name": "main"]]) == .some(.branch("main")))
        #expect(DaemonWire.checkout(fromResult: [:]) == nil)
        #expect(DaemonWire.checkout(fromResult: ["checkout": ["type": "mystery"]]) == nil)
    }

    @Test func branchesReadBack() {
        #expect(DaemonWire.branches(fromResult: ["branches": ["a", "b"]]) == ["a", "b"])
        #expect(DaemonWire.branches(fromResult: [:]) == nil)
    }
}
