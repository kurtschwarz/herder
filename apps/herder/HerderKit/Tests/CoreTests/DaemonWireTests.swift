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
            == #"{"client":"Herder 1.0","max_protocol":5,"min_protocol":4,"type":"hello"}"#)
    }

    @Test func aWelcomeIsConnected() {
        let status = DaemonWire.status(fromReply: json(
            #"{"type":"welcome","protocol":4,"daemon_version":"0.1.0","host":"local"}"#
        ))

        #expect(status == .connected(DaemonInfo(daemonVersion: "0.1.0", protocolVersion: 4, host: "local")))
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

    // MARK: - Replacing an old daemon

    @Test(arguments: [
        #"{"type":"incompatible","min_protocol":1,"max_protocol":1,"daemon_version":"0.1.0"}"#,
        #"{"type":"incompatible","min_protocol":1,"max_protocol":1,"daemon_version":"0.1.0","sessions":0}"#,
        // Protocol 2, the daemon the app that shipped git left running.
        #"{"type":"incompatible","min_protocol":2,"max_protocol":2,"daemon_version":"0.1.0","sessions":0}"#,
    ])
    func anOlderDaemonWithNoSessionsMayBeReplaced(reply: String) {
        #expect(DaemonWire.mayReplace(afterReply: json(reply)))
    }

    @Test(arguments: [
        // It owns sessions.
        #"{"type":"incompatible","min_protocol":1,"max_protocol":1,"daemon_version":"0.1.0","sessions":2}"#,
        // Newer than the app, so a newer app may be using it.
        #"{"type":"incompatible","min_protocol":9,"max_protocol":9,"daemon_version":"9.0.0","sessions":0}"#,
        // Reports its sessions as something that is not a count.
        #"{"type":"incompatible","min_protocol":0,"max_protocol":0,"daemon_version":"0.0.1","sessions":"none"}"#,
        #"{"type":"welcome","protocol":2,"daemon_version":"0.1.0","host":"local"}"#,
        "not json",
    ])
    func anyOtherDaemonIsLeftAlone(reply: String) {
        #expect(!DaemonWire.mayReplace(afterReply: json(reply)))
    }

    // MARK: - GitHub

    @Test func theTokenMessagesAreFlatJSON() {
        #expect(String(decoding: DaemonWire.setGitHubToken(id: 4, token: "ghu_x"), as: UTF8.self)
            == #"{"id":4,"token":"ghu_x","type":"set_github_token"}"#)
        #expect(String(decoding: DaemonWire.clearGitHubToken(id: 5), as: UTF8.self)
            == #"{"id":5,"type":"clear_github_token"}"#)
        #expect(String(decoding: DaemonWire.checkGitHub(id: 6), as: UTF8.self)
            == #"{"id":6,"type":"check_github"}"#)
    }

    @Test(arguments: [
        (#"{"type":"github_response","id":4,"check":{"state":"ok","login":"kurt"}}"#, GitHubCheck.ok(login: "kurt")),
        (#"{"type":"github_response","id":4,"check":{"state":"unauthorized"}}"#, .unauthorized),
        (#"{"type":"github_response","id":4,"check":{"state":"not_connected"}}"#, .notConnected),
        (#"{"type":"github_response","id":4,"check":{"state":"error","message":"GitHub answered 502"}}"#, .error("GitHub answered 502")),
    ])
    func aGitHubResponseSaysWhatTheCheckFound(reply: String, expected: GitHubCheck) {
        #expect(DaemonWire.gitHubCheck(fromReply: json(reply), id: 4) == expected)
    }

    @Test(arguments: [
        "not json",
        #"{"type":"github_response","id":9,"check":{"state":"ok","login":"kurt"}}"#,
        #"{"type":"github_response","id":4,"check":{"state":"ok"}}"#,
        #"{"type":"github_response","id":4,"check":{"state":"mystery"}}"#,
        #"{"type":"git_response","id":4,"result":{}}"#,
    ])
    func anythingElseIsAnErrorNotAGuess(reply: String) {
        guard case .error = DaemonWire.gitHubCheck(fromReply: json(reply), id: 4) else {
            Issue.record("expected an error for \(reply)")
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

    @Test func statusEntriesAreKeyedUnderTheRoot() throws {
        let root = PathKey(URL(filePath: "/tmp"))
        let status = try #require(DaemonWire.status(fromResult: [
            "root": "/tmp",
            "entries": [
                ["path": "a", "status": ["type": "untracked"]],
                ["path": "b", "status": ["type": "ignored"]],
                ["path": "c", "status": ["type": "unmerged"]],
                ["path": "d", "status": ["type": "tracked", "staged": "renamed", "unstaged": "type_changed"]],
            ],
        ], root: root))

        #expect(status.entries == [
            root.appending("a"): .untracked,
            root.appending("b"): .ignored,
            root.appending("c"): .unmerged,
            root.appending("d"): .tracked(staged: .renamed, unstaged: .typeChanged),
        ])
    }

    @Test func aStatusEntryItCannotReadIsNotAnAnswer() {
        let root = PathKey(URL(filePath: "/tmp"))
        let bad = ["entries": [["path": "a", "status": ["type": "mystery"]]]]
        #expect(DaemonWire.status(fromResult: bad, root: root) == nil)
        #expect(DaemonWire.status(fromResult: [:], root: root) == nil)
    }

    @Test func nullableAnswersKeepNullApartFromAMissingOne() {
        #expect(DaemonWire.mergeBase(fromResult: ["sha": "abc"]) == .some("abc"))
        #expect(DaemonWire.mergeBase(fromResult: ["sha": NSNull()]) == .some(nil))
        #expect(DaemonWire.mergeBase(fromResult: [:]) == nil)
        #expect(DaemonWire.upstream(fromResult: ["upstream": NSNull()]) == .some(nil))
        #expect(DaemonWire.fetchedBase(fromResult: ["base": "origin/main"]) == .some("origin/main"))
        #expect(DaemonWire.fetchedBase(fromResult: ["base": NSNull()]) == .some(nil))
        #expect(DaemonWire.fetchedBase(fromResult: [:]) == nil)
        #expect(DaemonWire.contents(fromResult: ["text": "x"]) == .some("x"))
        #expect(DaemonWire.changeSummary(fromResult: ["summary": NSNull()]) == .some(nil))
        #expect(DaemonWire.changeSummary(fromResult: ["summary": ["insertions": 2, "deletions": 1]])
            == .some(GitChangeSummary(insertions: 2, deletions: 1)))
        #expect(DaemonWire.changeSummary(fromResult: ["summary": ["insertions": 2]]) == nil)
    }

    @Test func commitsRefsAndChangedFilesReadBack() throws {
        let commit = ["sha": "abc", "subject": "first", "date": 10.0] as [String: Any]
        #expect(DaemonWire.commit(fromResult: ["commit": commit]) == .some(GitCommit(
            sha: "abc", subject: "first", date: Date(timeIntervalSince1970: 10)
        )))
        #expect(DaemonWire.commit(fromResult: ["commit": NSNull()]) == .some(nil))
        #expect(DaemonWire.commits(fromResult: ["commits": [commit, commit]])?.count == 2)
        #expect(DaemonWire.commits(fromResult: ["commits": [commit, ["sha": "x"]]]) == nil)

        let refs = try #require(DaemonWire.refs(fromResult: ["refs": [
            ["name": "main", "kind": "branch", "date": 5.0],
            ["name": "origin/main", "kind": "remote_branch", "date": 4.0],
            ["name": "v1", "kind": "tag", "date": 3.0],
        ]]))
        #expect(refs.map(\.kind) == [.branch, .remoteBranch, .tag])

        let files = try #require(DaemonWire.changedFiles(fromResult: ["files": [
            ["path": "b", "previous_path": "a", "status": "renamed", "insertions": 1, "deletions": 2],
            ["path": "c", "status": "added", "insertions": 0, "deletions": 0],
        ]]))
        #expect(files.map(\.previousPath) == ["a", nil])
        #expect(files.map(\.status) == [.renamed, .added])
        #expect(DaemonWire.changedFiles(fromResult: ["files": [["path": "c", "status": "mystery"]]]) == nil)
    }
    // MARK: Pull requests

    @Test func aPullRequestQueryIsOneFlatObjectOfRepositoriesAndBranches() throws {
        let payload = DaemonWire.pullRequestQuery(
            id: 4, repos: [PullRequestQuery(path: "/code/api", branches: ["feature", "fix/x"])]
        )

        #expect(String(decoding: payload, as: UTF8.self)
            == #"{"id":4,"repos":[{"branches":["feature","fix/x"],"path":"/code/api"}],"type":"pull_request_query"}"#)
    }

    @Test func readsAPullRequestResponse() throws {
        let reply = try #require(DaemonWire.pullRequests(fromReply: json("""
        {"type":"pull_request_response","id":4,"next_poll_seconds":240,"repos":[{
          "path":"/code/api","repository":"o/r","status":{"state":"ok"},"default_branch":"main",
          "branches":[
            {"branch":"feature","pull_request":{"number":7,"url":"https://github.com/o/r/pull/7",
              "title":"Add it","state":"merged","is_draft":false,
              "merged_at":"2026-01-03T00:00:00Z","updated_at":"2026-01-02T03:04:05Z"}},
            {"branch":"lonely","pull_request":null}
          ]
        },{
          "path":"/code/web","repository":"o/w","status":{"state":"not_accessible"},"branches":[]
        }]}
        """), id: 4))

        #expect(reply.nextPoll == .seconds(240))
        let api = try #require(reply.repositories.first)
        #expect(api.path == "/code/api")
        #expect(api.name == "o/r")
        #expect(api.status == .ok)
        #expect(api.defaultBranch == "main")
        let found = try #require(api.branches["feature"] ?? nil)
        #expect(found.number == 7)
        #expect(found.state == .merged)
        #expect(found.title == "Add it")
        #expect(found.updatedAt == Date(timeIntervalSince1970: 1_767_323_045))
        #expect(found.mergedAt == Date(timeIntervalSince1970: 1_767_398_400))
        #expect(api.branches["lonely"] == .some(nil))
        #expect(reply.repositories.last?.status == .notAccessible)
        #expect(reply.repositories.last?.defaultBranch == nil)
    }

    @Test func readsEveryRepositoryStatus() throws {
        func status(_ record: String) throws -> PullRequestReply.Status? {
            DaemonWire.pullRequests(fromReply: json("""
            {"type":"pull_request_response","id":1,"next_poll_seconds":60,"repos":[{
              "path":"/p","repository":"o/r","status":\(record),"branches":[]}]}
            """), id: 1)?.repositories.first?.status
        }

        #expect(try status(#"{"state":"unauthorized"}"#) == .unauthorized)
        #expect(try status(#"{"state":"error","message":"GitHub answered 502"}"#) == .error("GitHub answered 502"))
        #expect(try status(#"{"state":"something-newer"}"#) == nil)
    }

    @Test func aPullRequestStateThisBuildDoesNotKnowIsUnknown() throws {
        let reply = try #require(DaemonWire.pullRequests(fromReply: json("""
        {"type":"pull_request_response","id":1,"next_poll_seconds":60,"repos":[{
          "path":"/p","repository":"o/r","status":{"state":"ok"},"branches":[{"branch":"b","pull_request":{
          "number":1,"url":"https://github.com/o/r/pull/1","title":"t","state":"queued",
          "is_draft":false,"merged_at":null,"updated_at":"2026-01-02T03:04:05Z"}}]}]}
        """), id: 1))

        #expect(try #require(reply.repositories.first?.branches["b"] ?? nil).state == .unknown)
    }

    @Test func theAnswerToAnotherRequestIsNotAnAnswer() {
        let reply = json(#"{"type":"pull_request_response","id":5,"next_poll_seconds":60,"repos":[]}"#)

        #expect(DaemonWire.pullRequests(fromReply: reply, id: 4) == nil)
        #expect(DaemonWire.pullRequests(fromReply: reply, id: 5) != nil)
        #expect(DaemonWire.pullRequests(fromReply: json(#"{"type":"git_response","id":5}"#), id: 5) == nil)
    }
}
