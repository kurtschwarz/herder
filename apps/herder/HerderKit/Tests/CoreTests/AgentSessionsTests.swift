import Foundation
import Testing
import TestSupport

@testable import Core

/// Every agent session: what each window has open, what is written down, how
/// a session ends, and what is read back.
@Suite(.timeLimit(.minutes(1))) @MainActor struct AgentSessionsTests {
    let state = InMemoryStateStore()
    let clock = VirtualClockClient()
    let main = URL(filePath: "/code/api")
    let linked = URL(filePath: "/code/api-feature")
    let launch = Date(timeIntervalSince1970: 1_000_000)
    let window = UUID()
    let otherWindow = UUID()

    func makeSessions(launchedAt: Date? = nil) -> AgentSessions {
        AgentSessions(state: state, clock: clock, launchedAt: launchedAt ?? launch)
    }

    func session(
        _ id: UUID = UUID(),
        in worktree: URL? = nil,
        title: String = "Fix scroll jank",
        started: Date? = nil
    ) -> AgentSession {
        AgentSession(
            id: id, agentID: "claude-code", agentName: "Claude Code", sessionID: id.uuidString.lowercased(),
            worktree: WorkspaceID(worktree ?? main), branch: "main", title: title,
            startedAt: started ?? launch.addingTimeInterval(10)
        )
    }

    func report(
        _ id: UUID,
        in worktree: URL? = nil,
        title: String? = nil,
        sessionID: String? = nil,
        state: AgentSession.State = .idle
    ) -> AgentSessions.Report {
        AgentSessions.Report(
            id: id, worktree: WorkspaceID(worktree ?? main), agentID: "claude-code", agentName: "Claude Code",
            title: title, fallbackTitle: "Claude Code", sessionID: sessionID, state: state,
            lastActivity: launch
        )
    }

    var repository: PathKey { PathKey(main) }

    // MARK: Which repository

    @Test func everyWorktreeOfARepositoryIsOneHistory() async {
        let sessions = makeSessions()

        await sessions.begin(session(in: main), in: repository)
        await sessions.begin(session(in: linked), in: repository)

        #expect(sessions.recorded(in: repository).count == 2)
    }

    /// Whichever window wrote a repository's history, another listing the same
    /// folder reads it: the app has one store, keyed by the folder.
    @Test func aSecondWindowListsTheSameRepositorysHistory() async {
        let first = makeSessions()
        let ended = session(in: linked)
        await first.begin(ended, in: repository)
        first.end(ended.id, because: .closed)
        await first.flushSaves()

        let second = makeSessions(launchedAt: launch.addingTimeInterval(1000))
        await second.load(repository)

        #expect(second.ended(in: repository).map(\.id) == [ended.id])
    }

    @Test func repositoriesKeepSeparateHistories() async {
        let sessions = makeSessions()
        let other = PathKey(URL(filePath: "/code/web"))

        await sessions.begin(session(in: main), in: repository)
        await sessions.begin(session(in: URL(filePath: "/code/web")), in: other)

        #expect(sessions.recorded(in: repository).count == 1)
        #expect(sessions.recorded(in: other).count == 1)
    }

    // MARK: Ending

    @Test func aSessionIsOpenUntilItEnds() async {
        let sessions = makeSessions()
        let open = session()
        await sessions.begin(open, in: repository)

        #expect(sessions.ended(in: repository).isEmpty)

        let end = launch.addingTimeInterval(500)
        sessions.end(open.id, because: .closed, at: end)

        let ended = sessions.ended(in: repository)
        #expect(ended.map(\.id) == [open.id])
        #expect(ended.first?.endedAt == end)
        #expect(ended.first?.endReason == .closed)
    }

    @Test func aSessionThatEndedKeepsItsFirstEnd() async {
        let sessions = makeSessions()
        let open = session()
        await sessions.begin(open, in: repository)

        sessions.end(open.id, because: .exited, at: launch.addingTimeInterval(100))
        sessions.end(open.id, because: .closed, at: launch.addingTimeInterval(200))

        #expect(sessions.session(open.id)?.endReason == .exited)
    }

    @Test func aSessionNeverWrittenDownIsNotInTheStore() {
        let sessions = makeSessions()
        let id = UUID()
        sessions.note([report(id)], window: window)

        sessions.end(id, because: .closed)

        #expect(sessions.session(id) == nil)
    }

    /// What a tab is doing is the window's: the store keeps only what is
    /// written down.
    @Test func whatATabIsDoingIsNotKeptHere() async {
        let sessions = makeSessions()
        let open = session()
        await sessions.begin(open, in: repository)

        sessions.note([report(open.id, state: .working)], window: window)

        #expect(sessions.session(open.id)?.live == nil)
    }

    /// A working agent reports every second. Unless what is written down
    /// changes, the store must not, or every window watching it redraws.
    @Test func aReportThatChangesNothingWrittenDownChangesNothing() async {
        let sessions = makeSessions()
        let open = session()
        await sessions.begin(open, in: repository)
        let before = sessions.sessions

        sessions.note([report(open.id, state: .working)], window: window, at: open.startedAt.addingTimeInterval(5))

        #expect(sessions.sessions == before)
    }

    @Test func endedSessionsListLatestEndFirst() async {
        let sessions = makeSessions()
        let early = session(title: "early")
        let late = session(title: "late")
        await sessions.begin(early, in: repository)
        await sessions.begin(late, in: repository)

        sessions.end(late.id, because: .closed, at: launch.addingTimeInterval(100))
        sessions.end(early.id, because: .closed, at: launch.addingTimeInterval(200))

        #expect(sessions.ended(in: repository).map(\.title) == ["early", "late"])
    }

    @Test func resumingReopensTheSameSessionAndKeepsItsStart() async {
        let sessions = makeSessions()
        let open = session()
        await sessions.begin(open, in: repository)
        sessions.end(open.id, because: .closed, at: launch.addingTimeInterval(100))

        sessions.reopen(open.id, at: launch.addingTimeInterval(300))

        let reopened = sessions.session(open.id)
        #expect(reopened?.endedAt == nil)
        #expect(reopened?.endReason == nil)
        #expect(reopened?.startedAt == open.startedAt)
        #expect(sessions.recorded(in: repository).count == 1)
    }

    // MARK: What a tab says

    @Test func aTitleThatChangedIsKept() async {
        let sessions = makeSessions()
        let open = session(title: "Claude Code")
        await sessions.begin(open, in: repository)

        sessions.note([report(open.id, title: "Review tab dedupe")], window: window)

        #expect(sessions.session(open.id)?.title == "Review tab dedupe")
    }

    /// A paused tab has no title of its own yet, and must not put the agent's
    /// name over the one written down.
    @Test func aPausedTabKeepsTheTitleWrittenDown() async {
        let sessions = makeSessions()
        let open = session(title: "Review tab dedupe")
        await sessions.begin(open, in: repository)

        sessions.note([report(open.id, title: nil, state: .paused)], window: window)

        #expect(sessions.session(open.id)?.title == "Review tab dedupe")
    }

    @Test func aSessionIDFoundLaterIsKept() async {
        let sessions = makeSessions()
        var open = session()
        open.sessionID = nil
        await sessions.begin(open, in: repository)

        sessions.note([report(open.id, sessionID: "ses_abc")], window: window)
        sessions.note([report(open.id, sessionID: nil)], window: window)

        #expect(sessions.session(open.id)?.sessionID == "ses_abc")
    }

    @Test func lastSeenMovesOnlyOncePerMinuteAndOnlyWhileRunning() async {
        let sessions = makeSessions()
        let open = session()
        await sessions.begin(open, in: repository)

        sessions.note([report(open.id)], window: window, at: open.startedAt.addingTimeInterval(30))
        #expect(sessions.session(open.id)?.lastSeenAt == open.startedAt)

        let paused = open.startedAt.addingTimeInterval(61)
        sessions.note([report(open.id, state: .paused)], window: window, at: paused)
        #expect(sessions.session(open.id)?.lastSeenAt == open.startedAt)

        sessions.note([report(open.id)], window: window, at: paused)
        #expect(sessions.session(open.id)?.lastSeenAt == paused)
    }

    // MARK: After a crash

    @Test func anOpenSessionWithNoTabLeftEndsWhenItsWorktreeIsRestored() async {
        let sessions = makeSessions()
        var lost = session(started: launch.addingTimeInterval(-5000))
        lost.lastSeenAt = launch.addingTimeInterval(-4000)
        var kept = session(started: launch.addingTimeInterval(-5000))
        kept.lastSeenAt = launch.addingTimeInterval(-4000)
        await sessions.begin(lost, in: repository)
        await sessions.begin(kept, in: repository)

        await sessions.reconcile(WorkspaceID(main), in: repository, claimed: [kept.id])

        #expect(sessions.session(lost.id)?.endedAt == lost.lastSeenAt)
        #expect(sessions.session(lost.id)?.endReason == .unknown)
        #expect(sessions.session(kept.id)?.endedAt == nil)
    }

    @Test func aSessionSeenThisLaunchIsNotAnOrphan() async {
        let sessions = makeSessions()
        let fresh = session(started: launch.addingTimeInterval(10))
        await sessions.begin(fresh, in: repository)

        await sessions.reconcile(WorkspaceID(main), in: repository, claimed: [])

        #expect(sessions.session(fresh.id)?.endedAt == nil)
    }

    /// Another window restoring the same worktree has the tab too.
    @Test func aSessionWithATabInAnyWindowIsNotAnOrphan() async {
        let sessions = makeSessions()
        var old = session(started: launch.addingTimeInterval(-5000))
        old.lastSeenAt = launch.addingTimeInterval(-4000)
        await sessions.begin(old, in: repository)
        sessions.note([report(old.id, state: .paused)], window: otherWindow)

        await sessions.reconcile(WorkspaceID(main), in: repository, claimed: [])

        #expect(sessions.session(old.id)?.endedAt == nil)
    }

    @Test func otherWorktreesAreLeftAlone() async {
        let sessions = makeSessions()
        var elsewhere = session(in: linked, started: launch.addingTimeInterval(-5000))
        elsewhere.lastSeenAt = launch.addingTimeInterval(-4000)
        await sessions.begin(elsewhere, in: repository)

        await sessions.reconcile(WorkspaceID(main), in: repository, claimed: [])

        #expect(sessions.session(elsewhere.id)?.endedAt == nil)
    }

    // MARK: Saving and reading

    @Test func whatIsWrittenDownIsThereAfterARelaunch() async {
        let sessions = makeSessions()
        let open = session()
        await sessions.begin(open, in: repository)
        sessions.end(open.id, because: .exited, at: launch.addingTimeInterval(100))
        await sessions.flushSaves()

        let relaunched = makeSessions(launchedAt: launch.addingTimeInterval(1000))
        await relaunched.load(repository)

        #expect(relaunched.ended(in: repository).map(\.id) == [open.id])
        #expect(relaunched.session(open.id)?.endReason == .exited)
    }

    @Test func aDeletedSessionIsGoneAfterARelaunch() async {
        let sessions = makeSessions()
        let deleted = session()
        let kept = session()
        await sessions.begin(deleted, in: repository)
        await sessions.begin(kept, in: repository)
        sessions.end(deleted.id, because: .closed, at: launch.addingTimeInterval(100))
        sessions.end(kept.id, because: .closed, at: launch.addingTimeInterval(100))
        await sessions.flushSaves()

        sessions.delete(deleted.id)
        await sessions.flushSaves()

        #expect(sessions.session(deleted.id) == nil)
        let relaunched = makeSessions(launchedAt: launch.addingTimeInterval(1000))
        await relaunched.load(repository)
        #expect(relaunched.recorded(in: repository).map(\.id) == [kept.id])
    }

    @Test func aRenamedSessionKeepsItsNameAfterARelaunch() async {
        let sessions = makeSessions()
        let ended = session()
        await sessions.begin(ended, in: repository)
        sessions.end(ended.id, because: .closed, at: launch.addingTimeInterval(100))

        sessions.rename(ended.id, to: "  Scroll fix  ")
        await sessions.flushSaves()

        let relaunched = makeSessions(launchedAt: launch.addingTimeInterval(1000))
        await relaunched.load(repository)
        #expect(relaunched.session(ended.id)?.title == "Scroll fix")
        #expect(relaunched.session(ended.id)?.name == "Scroll fix")
    }

    @Test func aBlankNameChangesNothing() async {
        let sessions = makeSessions()
        let ended = session()
        await sessions.begin(ended, in: repository)
        sessions.end(ended.id, because: .closed)

        sessions.rename(ended.id, to: " ")

        #expect(sessions.session(ended.id)?.title == ended.title)
        #expect(sessions.session(ended.id)?.name == nil)
    }

    @Test func anOpenSessionIsNotRenamedHere() async {
        let sessions = makeSessions()
        let open = session()
        await sessions.begin(open, in: repository)

        sessions.rename(open.id, to: "Scroll fix")

        #expect(sessions.session(open.id)?.title == open.title)
    }

    @Test func anOpenSessionIsNotDeleted() async {
        let sessions = makeSessions()
        let open = session()
        await sessions.begin(open, in: repository)

        sessions.delete(open.id)

        #expect(sessions.session(open.id) != nil)
    }

    @Test func aSessionWrittenDownWhileTheFileIsReadingIsNotLost() async {
        let first = makeSessions()
        let old = session()
        await first.begin(old, in: repository)
        await first.flushSaves()

        let relaunched = makeSessions()
        let new = session()
        async let begun: Void = relaunched.begin(new, in: repository)
        async let loaded: Void = relaunched.load(repository)
        _ = await (begun, loaded)

        #expect(Set(relaunched.recorded(in: repository).map(\.id)) == [old.id, new.id])
    }

    @Test func aRepositoryIsKeyedByItsPath() {
        // The key is the path of the folder the repository was added as,
        // which is all that survives removing it and adding it back.
        #expect(SessionHistorySnapshot.persistenceKey(for: repository) == "history:/code/api")
    }

    // MARK: Bytes this build did not write

    @Test func aSessionWrittenByAnEarlierBuildStillReads() throws {
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

        let session = try #require(snapshot.records.first)
        #expect(session.agentName == "codex")
        #expect(session.title == "codex")
        #expect(session.sessionID == nil)
        #expect(session.branch == nil)
        #expect(session.lastSeenAt == session.startedAt)
        #expect(session.endReason == .unknown)
        #expect(session.live == nil)
    }
}
