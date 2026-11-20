import Foundation
import Synchronization
import Testing
import TestSupport

@testable import Core

/// Polling herderd for each session's pull request, and linking what it finds.
@Suite(.timeLimit(.minutes(1))) @MainActor struct LinkedPullRequestsTests {
    let state = InMemoryStateStore()
    let launch = Date(timeIntervalSince1970: 1_000_000)
    let api = PathKey(URL(filePath: "/code/api"))
    let web = PathKey(URL(filePath: "/code/web"))

    // MARK: Fixtures

    /// A herderd that answers each query from a script, and remembers them.
    final class Daemon: Sendable {
        struct Script {
            /// Each answer's repositories, as JSON.
            var replies: [Data] = []
            var nextPoll = 60
            var queries: [[PullRequestQuery]] = []
        }

        let stub = StubDaemonClient()
        private let script = Mutex(Script())

        init() {
            stub.respond { [unowned self] payload in
                let request = try JSONSerialization.jsonObject(with: payload) as! [String: Any]
                let repos = (request["repos"] as! [[String: Any]]).map {
                    PullRequestQuery(path: $0["path"] as! String, branches: $0["branches"] as! [String])
                }
                return try self.script.withLock { script in
                    script.queries.append(repos)
                    let next = script.replies.isEmpty ? [] : try JSONSerialization.jsonObject(
                        with: script.replies.removeFirst()
                    ) as! [[String: Any]]
                    let reply: [String: Any] = [
                        "type": "pull_request_response", "id": request["id"]!,
                        "repos": next, "next_poll_seconds": script.nextPoll,
                    ]
                    return try JSONSerialization.data(withJSONObject: reply)
                }
            }
        }

        /// What the next poll's answer holds, one entry per repository.
        func answer(_ repos: [[String: Any]], nextPoll: Int = 60) {
            let encoded = try! JSONSerialization.data(withJSONObject: repos)
            script.withLock {
                $0.replies.append(encoded)
                $0.nextPoll = nextPoll
            }
        }

        var queries: [[PullRequestQuery]] { script.withLock { $0.queries } }
    }

    /// A clock whose sleeps return at once, and which stops the loop that is
    /// sleeping on it after `limit` of them.
    final class StoppingClock: ClockClient {
        private let slept = Mutex<[Duration]>([])
        private let limit: Int
        init(after limit: Int) { self.limit = limit }

        var sleeps: [Duration] { slept.withLock { $0 } }
        var now: ContinuousClock.Instant { .now }

        func sleep(for duration: Duration) async throws {
            let count = slept.withLock { slept in
                slept.append(duration)
                return slept.count
            }
            if count >= limit { throw CancellationError() }
            await Task.yield()
        }
    }

    func session(
        branch: String?,
        in worktree: String = "/code/api",
        ended: Bool = false,
        pullRequest: LinkedPullRequest? = nil
    ) -> AgentSession {
        AgentSession(
            id: UUID(), agentID: "claude-code", agentName: "Claude Code", sessionID: nil,
            worktree: WorkspaceID(URL(filePath: worktree)), branch: branch, title: "Work",
            startedAt: launch, endedAt: ended ? launch.addingTimeInterval(60) : nil,
            endReason: ended ? .closed : nil, pullRequest: pullRequest
        )
    }

    func pullRequest(
        _ number: Int = 7, state: LinkedPullRequest.State = .open, isDraft: Bool = false
    ) -> LinkedPullRequest {
        LinkedPullRequest(
            number: number, url: URL(string: "https://github.com/o/r/pull/\(number)")!, title: "Pull \(number)",
            // What `repo(_:branches:)` words it as.
            state: state, isDraft: isDraft, updatedAt: Date(timeIntervalSince1970: 1_767_323_045)
        )
    }

    /// The answer for one repository, as herderd words it.
    func repo(
        _ path: PathKey,
        name: String = "o/r",
        status: [String: Any] = ["state": "ok"],
        defaultBranch: String? = "main",
        branches: [String: LinkedPullRequest?] = [:]
    ) -> [String: Any] {
        var record: [String: Any] = [
            "path": path.path, "repository": name, "status": status,
            "branches": branches.map { branch, found -> [String: Any] in
                var entry: [String: Any] = ["branch": branch]
                if let found {
                    entry["pull_request"] = [
                        "number": found.number, "url": found.url.absoluteString, "title": found.title,
                        "state": "\(found.state)", "is_draft": found.isDraft,
                        "updated_at": "2026-01-02T03:04:05Z",
                    ] as [String: Any]
                }
                return entry
            },
        ]
        if let defaultBranch { record["default_branch"] = defaultBranch }
        return record
    }

    func makeSessions() -> AgentSessions {
        AgentSessions(state: state, clock: VirtualClockClient(), launchedAt: launch)
    }

    func makePoller(
        _ sessions: AgentSessions,
        daemon: Daemon,
        clock: any ClockClient = VirtualClockClient(),
        refused: @escaping @MainActor () async -> Void = {}
    ) -> LinkedPullRequests {
        LinkedPullRequests(sessions: sessions, daemon: daemon.stub, clock: clock, signInRefused: refused)
    }

    // MARK: Polling

    @Test func asksOnTheIntervalHerderdGives() async {
        let sessions = makeSessions()
        await sessions.begin(session(branch: "feature"), in: api)
        let daemon = Daemon()
        let clock = StoppingClock(after: 3)
        let poller = makePoller(sessions, daemon: daemon, clock: clock)
        for _ in 0..<3 { daemon.answer([repo(api, branches: ["feature": nil])]) }

        await poller.run()

        #expect(clock.sleeps == [.seconds(60), .seconds(60), .seconds(60)])
        #expect(daemon.queries.count == 3)
    }

    @Test func aLongerWaitFromHerderdIsObeyed() async {
        let sessions = makeSessions()
        await sessions.begin(session(branch: "feature"), in: api)
        let daemon = Daemon()
        let clock = StoppingClock(after: 1)
        daemon.answer([repo(api, status: ["state": "error", "message": "GitHub answered 502"])], nextPoll: 240)

        await makePoller(sessions, daemon: daemon, clock: clock).run()

        #expect(clock.sleeps == [.seconds(240)])
    }

    @Test func oneQueryCarriesEveryRepositoryAndBranch() async {
        let sessions = makeSessions()
        await sessions.begin(session(branch: "one"), in: api)
        await sessions.begin(session(branch: "two"), in: api)
        await sessions.begin(session(branch: "three", in: "/code/web"), in: web)
        let daemon = Daemon()
        daemon.answer([])

        _ = await makePoller(sessions, daemon: daemon).poll()

        #expect(daemon.queries == [[
            PullRequestQuery(path: api.path, branches: ["one", "two"]),
            PullRequestQuery(path: web.path, branches: ["three"]),
        ]])
    }

    @Test func withNothingToWatchNothingIsAsked() async {
        let sessions = makeSessions()
        let daemon = Daemon()

        let wait = await makePoller(sessions, daemon: daemon).poll()

        #expect(daemon.queries.isEmpty)
        #expect(wait == LinkedPullRequests.idleInterval)
    }

    // MARK: Which branches

    @Test func watchesOpenSessionsAndEndedOnesWhoseRequestIsOpen() async {
        let sessions = makeSessions()
        await sessions.begin(session(branch: "running"), in: api)
        await sessions.begin(session(branch: "open-pr", ended: true, pullRequest: pullRequest(state: .open)), in: api)
        await sessions.begin(session(branch: "unknown-pr", ended: true, pullRequest: pullRequest(state: .unknown)), in: api)

        #expect(sessions.watchedBranches() == [api: ["running", "open-pr", "unknown-pr"]])
    }

    @Test func leavesOutWhatHasNothingToFind() async {
        let sessions = makeSessions()
        await sessions.begin(session(branch: "ended-without", ended: true), in: api)
        await sessions.begin(session(branch: "merged", pullRequest: pullRequest(state: .merged)), in: api)
        await sessions.begin(session(branch: "closed", pullRequest: pullRequest(state: .closed)), in: api)
        await sessions.begin(session(branch: "ended-merged", ended: true, pullRequest: pullRequest(state: .merged)), in: api)
        await sessions.begin(session(branch: "3f9a1c2"), in: api)
        await sessions.begin(session(branch: nil), in: api)

        #expect(sessions.watchedBranches().isEmpty)
    }

    @Test func aBranchNamedLikeAWordIsNotACommit() async {
        let sessions = makeSessions()
        await sessions.begin(session(branch: "feature"), in: api)
        await sessions.begin(session(branch: "release-1.2"), in: api)

        #expect(sessions.watchedBranches() == [api: ["feature", "release-1.2"]])
    }

    @Test func stopsAskingAboutTheDefaultBranchOnceHerderdHasSaidWhichItIs() async {
        let sessions = makeSessions()
        await sessions.begin(session(branch: "main"), in: api)
        await sessions.begin(session(branch: "feature"), in: api)
        let daemon = Daemon()
        daemon.answer([repo(api, defaultBranch: "main", branches: ["main": nil, "feature": nil])])
        daemon.answer([repo(api, defaultBranch: "main", branches: ["feature": nil])])
        let poller = makePoller(sessions, daemon: daemon)

        _ = await poller.poll()
        _ = await poller.poll()

        #expect(daemon.queries.map { $0.map(\.branches) } == [[["feature", "main"]], [["feature"]]])
    }

    // MARK: Linking

    @Test func everySessionOfTheBranchInTheRepositoryGetsIt() async {
        let sessions = makeSessions()
        let first = session(branch: "feature", in: "/code/api")
        let second = session(branch: "feature", in: "/code/api-feature")
        let ended = session(branch: "feature", ended: true)
        let otherBranch = session(branch: "other")
        let otherRepository = session(branch: "feature", in: "/code/web")
        for each in [first, second, ended, otherBranch] { await sessions.begin(each, in: api) }
        await sessions.begin(otherRepository, in: web)
        let daemon = Daemon()
        daemon.answer([repo(api, branches: ["feature": pullRequest(7)])])

        _ = await makePoller(sessions, daemon: daemon).poll()

        #expect(sessions.session(first.id)?.pullRequest?.number == 7)
        #expect(sessions.session(second.id)?.pullRequest?.number == 7)
        #expect(sessions.session(ended.id)?.pullRequest?.number == 7)
        #expect(sessions.session(otherBranch.id)?.pullRequest == nil)
        #expect(sessions.session(otherRepository.id)?.pullRequest == nil)
    }

    @Test func aNewerPullRequestReplacesTheOneThere() async {
        let sessions = makeSessions()
        let one = session(branch: "feature", pullRequest: pullRequest(7, state: .open))
        await sessions.begin(one, in: api)
        let daemon = Daemon()
        daemon.answer([repo(api, branches: ["feature": pullRequest(9, state: .open)])])

        _ = await makePoller(sessions, daemon: daemon).poll()

        #expect(sessions.session(one.id)?.pullRequest?.number == 9)
    }

    @Test func aBranchWithNoPullRequestKeepsWhatItHad() async {
        let sessions = makeSessions()
        let one = session(branch: "feature", pullRequest: pullRequest(7))
        await sessions.begin(one, in: api)
        let daemon = Daemon()
        daemon.answer([repo(api, branches: ["feature": nil])])

        _ = await makePoller(sessions, daemon: daemon).poll()

        #expect(sessions.session(one.id)?.pullRequest?.number == 7)
    }

    @Test func stopsAskingAboutABranchOnceItsPullRequestIsMergedOrClosed() async {
        let sessions = makeSessions()
        await sessions.begin(session(branch: "merging"), in: api)
        await sessions.begin(session(branch: "closing"), in: api)
        await sessions.begin(session(branch: "waiting"), in: api)
        let daemon = Daemon()
        daemon.answer([repo(api, branches: [
            "merging": pullRequest(1, state: .merged), "closing": pullRequest(2, state: .closed),
            "waiting": pullRequest(3, state: .open),
        ])])
        daemon.answer([repo(api, branches: ["waiting": pullRequest(3, state: .open)])])
        let poller = makePoller(sessions, daemon: daemon)

        _ = await poller.poll()
        _ = await poller.poll()

        #expect(daemon.queries.map { $0.flatMap(\.branches) } == [["closing", "merging", "waiting"], ["waiting"]])
    }

    @Test func aMergeIsRecorded() async throws {
        let sessions = makeSessions()
        let one = session(branch: "feature", pullRequest: pullRequest(7, state: .open))
        await sessions.begin(one, in: api)
        let daemon = Daemon()
        daemon.answer([repo(api, branches: ["feature": pullRequest(7, state: .merged)])])

        _ = await makePoller(sessions, daemon: daemon).poll()

        #expect(try #require(sessions.session(one.id)?.pullRequest).state == .merged)
        #expect(sessions.watchedBranches().isEmpty)
    }

    @Test func theLinkSurvivesARelaunch() async throws {
        let sessions = makeSessions()
        let one = session(branch: "feature")
        await sessions.begin(one, in: api)
        let daemon = Daemon()
        daemon.answer([repo(api, branches: ["feature": pullRequest(7, state: .merged, isDraft: true)])])
        _ = await makePoller(sessions, daemon: daemon).poll()
        await sessions.flushSaves()

        let relaunched = makeSessions()
        await relaunched.load(api)

        let linked = try #require(relaunched.session(one.id)?.pullRequest)
        #expect(linked == pullRequest(7, state: .merged, isDraft: true))
    }

    // MARK: Failures

    @Test func aRefusedTokenAsksForOneRefresh() async {
        let sessions = makeSessions()
        await sessions.begin(session(branch: "feature"), in: api)
        let daemon = Daemon()
        daemon.answer([repo(api, status: ["state": "unauthorized"])])
        let refreshes = Mutex(0)
        let poller = makePoller(sessions, daemon: daemon) { refreshes.withLock { $0 += 1 } }

        _ = await poller.poll()

        #expect(refreshes.withLock { $0 } == 1)
    }

    @Test func repositoriesTheAppCannotSeeAreListedUntilItCan() async {
        let sessions = makeSessions()
        await sessions.begin(session(branch: "feature"), in: api)
        await sessions.begin(session(branch: "feature", in: "/code/web"), in: web)
        let daemon = Daemon()
        daemon.answer([
            repo(api, name: "o/api", status: ["state": "not_accessible"]),
            repo(web, name: "o/web"),
        ])
        daemon.answer([repo(api, name: "o/api"), repo(web, name: "o/web")])
        let poller = makePoller(sessions, daemon: daemon)

        _ = await poller.poll()
        #expect(poller.inaccessible.map(\.name) == ["o/api"])

        _ = await poller.poll()
        #expect(poller.inaccessible.isEmpty)
    }

    @Test func aGitHubErrorIsKeptForSettingsAndLinksWhatHerderdStillHas() async {
        let sessions = makeSessions()
        let one = session(branch: "feature")
        await sessions.begin(one, in: api)
        let daemon = Daemon()
        daemon.answer(
            [repo(api, status: ["state": "error", "message": "GitHub answered 502"], branches: ["feature": pullRequest(7)])],
            nextPoll: 120
        )
        let poller = makePoller(sessions, daemon: daemon)

        let wait = await poller.poll()

        #expect(wait == .seconds(120))
        #expect(poller.lastError == "GitHub answered 502")
        #expect(sessions.session(one.id)?.pullRequest?.number == 7)
    }

    @Test func aHerderdThatCannotBeReachedIsAskedLessAndLessOften() async {
        let sessions = makeSessions()
        await sessions.begin(session(branch: "feature"), in: api)
        let daemon = Daemon()
        daemon.stub.respond { _ in throw StubDaemonClientError.unreachable }
        let poller = makePoller(sessions, daemon: daemon)

        var waits: [Duration] = []
        for _ in 0..<6 { waits.append(await poller.poll()) }

        #expect(waits == [60, 120, 240, 480, 600, 600].map { Duration.seconds($0) })
        #expect(poller.lastError != nil)
    }

    @Test func anAnswerResetsTheWaitAndClearsTheError() async {
        let sessions = makeSessions()
        await sessions.begin(session(branch: "feature"), in: api)
        let daemon = Daemon()
        let poller = makePoller(sessions, daemon: daemon)
        daemon.stub.respond { _ in throw StubDaemonClientError.unreachable }
        _ = await poller.poll()
        let second = await poller.poll()
        #expect(second == .seconds(120))

        daemon.stub.respond { payload in
            let request = try JSONSerialization.jsonObject(with: payload) as! [String: Any]
            return try JSONSerialization.data(withJSONObject: [
                "type": "pull_request_response", "id": request["id"]!, "repos": [], "next_poll_seconds": 60,
            ] as [String: Any])
        }
        let third = await poller.poll()

        #expect(third == .seconds(60))
        #expect(poller.lastError == nil)
    }

    // MARK: Bytes this build did not write

    @Test func historyWithoutALinkedPullRequestStillReads() throws {
        let json = """
        {"version": 1, "records": [{
          "id": "3F2504E0-4F89-41D3-9A0C-0305E82C3301", "agentID": "codex",
          "worktree": "/code/api", "branch": "feature", "startedAt": 1000
        }]}
        """
        let snapshot = try JSONDecoder().decode(SessionHistorySnapshot.self, from: Data(json.utf8))

        #expect(try #require(snapshot.records.first).pullRequest == nil)
    }

    @Test func aLinkedPullRequestInAStateThisBuildDoesNotKnowReadsAsUnknown() throws {
        let json = """
        {"version": 1, "records": [{
          "id": "3F2504E0-4F89-41D3-9A0C-0305E82C3301", "agentID": "codex",
          "worktree": "/code/api", "branch": "feature", "startedAt": 1000,
          "pullRequest": {
            "number": 12, "url": "https://github.com/o/r/pull/12", "title": "Add it",
            "state": "queued", "isDraft": true, "updatedAt": 2000
          }
        }]}
        """
        let snapshot = try JSONDecoder().decode(SessionHistorySnapshot.self, from: Data(json.utf8))

        let linked = try #require(snapshot.records.first?.pullRequest)
        #expect(linked.number == 12)
        #expect(linked.state == .unknown)
        #expect(linked.isDraft)
        #expect(linked.mergedAt == nil)
    }
}
