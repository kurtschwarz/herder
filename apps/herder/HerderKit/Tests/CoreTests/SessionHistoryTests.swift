import Foundation
import Testing
import TestSupport

@testable import Core

/// The history of agent sessions: what is written down, how it ends, and what
/// is read back.
@Suite(.timeLimit(.minutes(1))) @MainActor struct SessionHistoryTests {
    let git = StubGitClient()
    let state = InMemoryStateStore()
    let clock = VirtualClockClient()
    let main = URL(filePath: "/code/api")
    let linked = URL(filePath: "/code/api-feature")
    let launch = Date(timeIntervalSince1970: 1_000_000)

    init() {
        git.seed(
            worktrees: [
                GitWorktree(path: main, checkout: .branch("main"), isMainWorkingTree: true),
                GitWorktree(path: linked, checkout: .branch("feature"), isMainWorkingTree: false),
            ],
            at: linked
        )
        git.seed(
            worktrees: [
                GitWorktree(path: main, checkout: .branch("main"), isMainWorkingTree: true),
                GitWorktree(path: linked, checkout: .branch("feature"), isMainWorkingTree: false),
            ],
            at: main
        )
    }

    func makeHistory(launchedAt: Date? = nil) -> SessionHistory {
        SessionHistory(git: git, state: state, clock: clock, launchedAt: launchedAt ?? launch)
    }

    func record(
        _ id: UUID = UUID(),
        in worktree: URL? = nil,
        title: String = "Fix scroll jank",
        started: Date? = nil
    ) -> SessionHistoryRecord {
        SessionHistoryRecord(
            id: id, agentID: "claude-code", agentName: "Claude Code", sessionID: id.uuidString.lowercased(),
            worktree: WorkspaceID(worktree ?? main), branch: "main", title: title,
            startedAt: started ?? launch.addingTimeInterval(10)
        )
    }

    var repository: PathKey { PathKey(main) }

    // MARK: Which repository

    @Test func everyWorktreeOfARepositoryIsOneHistory() async {
        let history = makeHistory()
        let first = record(in: main)
        let second = record(in: linked)

        await history.begin(first)
        await history.begin(second)

        #expect(history.repositories[repository]?.count == 2)
    }

    @Test func aBareRepositoryIsKeyedByItsFirstWorktree() {
        let worktrees = [
            GitWorktree(path: URL(filePath: "/code/b"), checkout: .branch("b"), isMainWorkingTree: false),
            GitWorktree(path: URL(filePath: "/code/a"), checkout: .branch("a"), isMainWorkingTree: false),
        ]
        let key = SessionHistory.repositoryKey(for: worktrees, fallback: PathKey(URL(filePath: "/code")))
        #expect(key == PathKey(URL(filePath: "/code/a")))
    }

    // MARK: Ending

    @Test func aSessionIsOpenUntilItEnds() async {
        let history = makeHistory()
        let open = record()
        await history.begin(open)

        #expect(history.ended(in: repository).isEmpty)

        let end = launch.addingTimeInterval(500)
        history.end(open.id, because: .closed, at: end)

        let ended = history.ended(in: repository)
        #expect(ended.map(\.id) == [open.id])
        #expect(ended.first?.endedAt == end)
        #expect(ended.first?.endReason == .closed)
    }

    @Test func aSessionThatEndedKeepsItsFirstEnd() async {
        let history = makeHistory()
        let open = record()
        await history.begin(open)

        history.end(open.id, because: .exited, at: launch.addingTimeInterval(100))
        history.end(open.id, because: .closed, at: launch.addingTimeInterval(200))

        #expect(history.record(open.id)?.endReason == .exited)
    }

    @Test func endedSessionsListLatestEndFirst() async {
        let history = makeHistory()
        let early = record(title: "early")
        let late = record(title: "late")
        await history.begin(early)
        await history.begin(late)

        history.end(late.id, because: .closed, at: launch.addingTimeInterval(100))
        history.end(early.id, because: .closed, at: launch.addingTimeInterval(200))

        #expect(history.ended(in: repository).map(\.title) == ["early", "late"])
    }

    @Test func resumingReopensTheSameRecordAndKeepsItsStart() async {
        let history = makeHistory()
        let open = record()
        await history.begin(open)
        history.end(open.id, because: .closed, at: launch.addingTimeInterval(100))

        history.reopen(open.id, at: launch.addingTimeInterval(300))

        let reopened = history.record(open.id)
        #expect(reopened?.endedAt == nil)
        #expect(reopened?.endReason == nil)
        #expect(reopened?.startedAt == open.startedAt)
        #expect(history.repositories[repository]?.count == 1)
    }

    // MARK: Touching

    @Test func aTitleThatChangedIsKept() async {
        let history = makeHistory()
        let open = record(title: "Claude Code")
        await history.begin(open)

        history.touch(open.id, title: "Review tab dedupe", sessionID: nil, at: open.startedAt)

        #expect(history.record(open.id)?.title == "Review tab dedupe")
    }

    @Test func aSessionIDFoundLaterIsKept() async {
        let history = makeHistory()
        var open = record()
        open.sessionID = nil
        await history.begin(open)

        history.touch(open.id, title: open.title, sessionID: "ses_abc", at: open.startedAt)
        history.touch(open.id, title: open.title, sessionID: nil, at: open.startedAt)

        #expect(history.record(open.id)?.sessionID == "ses_abc")
    }

    @Test func lastSeenMovesOnlyOncePerMinute() async {
        let history = makeHistory()
        let open = record()
        await history.begin(open)

        history.touch(open.id, title: open.title, sessionID: nil, at: open.startedAt.addingTimeInterval(30))
        #expect(history.record(open.id)?.lastSeenAt == open.startedAt)

        history.touch(open.id, title: open.title, sessionID: nil, at: open.startedAt.addingTimeInterval(61))
        #expect(history.record(open.id)?.lastSeenAt == open.startedAt.addingTimeInterval(61))
    }

    // MARK: After a crash

    @Test func anOpenSessionWithNoTabLeftEndsWhenItsWorktreeIsRestored() async {
        let history = makeHistory()
        var lost = record(started: launch.addingTimeInterval(-5000))
        lost.lastSeenAt = launch.addingTimeInterval(-4000)
        var kept = record(started: launch.addingTimeInterval(-5000))
        kept.lastSeenAt = launch.addingTimeInterval(-4000)
        await history.begin(lost)
        await history.begin(kept)

        await history.reconcile(WorkspaceID(main), claimed: [kept.id])

        #expect(history.record(lost.id)?.endedAt == lost.lastSeenAt)
        #expect(history.record(lost.id)?.endReason == .unknown)
        #expect(history.record(kept.id)?.endedAt == nil)
    }

    @Test func aSessionSeenThisLaunchIsNotAnOrphan() async {
        let history = makeHistory()
        let fresh = record(started: launch.addingTimeInterval(10))
        await history.begin(fresh)

        await history.reconcile(WorkspaceID(main), claimed: [])

        #expect(history.record(fresh.id)?.endedAt == nil)
    }

    @Test func otherWorktreesAreLeftAlone() async {
        let history = makeHistory()
        var elsewhere = record(in: linked, started: launch.addingTimeInterval(-5000))
        elsewhere.lastSeenAt = launch.addingTimeInterval(-4000)
        await history.begin(elsewhere)

        await history.reconcile(WorkspaceID(main), claimed: [])

        #expect(history.record(elsewhere.id)?.endedAt == nil)
    }

    // MARK: Saving and reading

    @Test func whatIsWrittenDownIsThereAfterARelaunch() async {
        let history = makeHistory()
        let open = record()
        await history.begin(open)
        history.end(open.id, because: .exited, at: launch.addingTimeInterval(100))
        await history.flushSaves()

        let relaunched = makeHistory(launchedAt: launch.addingTimeInterval(1000))
        await relaunched.load(repository)

        #expect(relaunched.ended(in: repository).map(\.id) == [open.id])
        #expect(relaunched.record(open.id)?.endReason == .exited)
    }

    @Test func aRecordMadeWhileTheFileIsReadingIsNotLost() async {
        let first = makeHistory()
        let old = record()
        await first.begin(old)
        await first.flushSaves()

        let relaunched = makeHistory()
        let new = record()
        async let begun: Void = relaunched.begin(new)
        async let loaded: Void = relaunched.load(repository)
        _ = await (begun, loaded)

        #expect(Set(relaunched.repositories[repository]?.map(\.id) ?? []) == [old.id, new.id])
    }

    @Test func aRepositoryReadsTheSameWhateverItsID() async {
        // The key is the path of the main working tree, which is all that
        // survives removing a repository and adding it back.
        #expect(SessionHistorySnapshot.persistenceKey(for: repository) == "history:/code/api")
    }

    // MARK: Bytes this build did not write

    @Test func aRecordWrittenByAnEarlierBuildStillReads() throws {
        let json = """
        {
          "version": 1,
          "records": [{
            "id": "3F2504E0-4F89-41D3-9A0C-0305E82C3301",
            "agentID": "codex",
            "worktree": "/code/api",
            "startedAt": 1000,
            "endedAt": 2000,
            "endReason": "something-newer"
          }]
        }
        """
        let snapshot = try JSONDecoder().decode(SessionHistorySnapshot.self, from: Data(json.utf8))

        let record = try #require(snapshot.records.first)
        #expect(record.agentName == "codex")
        #expect(record.title == "codex")
        #expect(record.sessionID == nil)
        #expect(record.branch == nil)
        #expect(record.lastSeenAt == record.startedAt)
        #expect(record.endReason == .unknown)
    }
}
