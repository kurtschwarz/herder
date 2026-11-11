import Foundation
import Testing
import TestSupport

@testable import Core

/// What one window has open: listed from the app-wide records, with what each
/// tab is doing over them, and never shared with another window.
@Suite(.timeLimit(.minutes(1))) @MainActor struct WindowAgentSessionsTests {
    let state = InMemoryStateStore()
    let clock = VirtualClockClient()
    let main = URL(filePath: "/code/api")
    let launch = Date(timeIntervalSince1970: 1_000_000)
    let store: AgentSessions

    init() {
        store = AgentSessions(state: state, clock: clock, launchedAt: launch)
    }

    var repository: PathKey { PathKey(main) }

    func session(_ id: UUID = UUID(), title: String = "Fix scroll jank") -> AgentSession {
        AgentSession(
            id: id, agentID: "claude-code", agentName: "Claude Code", sessionID: id.uuidString.lowercased(),
            worktree: WorkspaceID(main), branch: "main", title: title, startedAt: launch.addingTimeInterval(10)
        )
    }

    func report(_ id: UUID, title: String? = nil, state: AgentSession.State = .idle) -> AgentSessions.Report {
        AgentSessions.Report(
            id: id, worktree: WorkspaceID(main), agentID: "claude-code", agentName: "Claude Code",
            title: title, fallbackTitle: "Claude Code", sessionID: nil, state: state, lastActivity: launch
        )
    }

    @Test func aWindowListsWhatItReportedInItsOrder() {
        let open = WindowAgentSessions(store: store)
        let first = UUID()
        let second = UUID()

        open.publish([report(first), report(second)], focused: second)

        #expect(open.sessions.map(\.id) == [first, second])
        #expect(open.focused == second)
    }

    @Test func eachWindowListsOnlyItsOwn() {
        let mine = WindowAgentSessions(store: store)
        let theirs = WindowAgentSessions(store: store)
        let a = UUID()
        let b = UUID()

        mine.publish([report(a)], focused: a)
        theirs.publish([report(b)], focused: b)

        #expect(mine.sessions.map(\.id) == [a])
        #expect(theirs.sessions.map(\.id) == [b])
    }

    @Test func whatATabIsDoingIsListedHereAndNotInTheStore() async {
        let open = WindowAgentSessions(store: store)
        let written = session()
        await store.begin(written, in: repository)

        open.publish([report(written.id, state: .working)], focused: nil)

        #expect(open.sessions.first?.state == .working)
        #expect(store.session(written.id)?.live == nil)
    }

    @Test func aTabThatNeverRanIsListedHereAlone() {
        let open = WindowAgentSessions(store: store)
        let id = UUID()

        open.publish([report(id, state: .failed)], focused: id)

        #expect(open.sessions.map(\.title) == ["Claude Code"])
        #expect(store.session(id) == nil)

        open.publish([], focused: nil)

        #expect(open.sessions.isEmpty)
    }

    @Test func aSessionWrittenDownOutlivesItsTab() async {
        let open = WindowAgentSessions(store: store)
        let written = session()
        open.publish([report(written.id)], focused: written.id)
        await store.begin(written, in: repository)

        open.publish([], focused: nil)

        #expect(open.sessions.isEmpty)
        #expect(store.session(written.id)?.isEnded == false)
    }

    /// A paused tab has no title of its own, so it is listed with the one
    /// written down rather than its agent's name.
    @Test func aPausedTabIsListedWithTheTitleWrittenDown() async {
        let open = WindowAgentSessions(store: store)
        let written = session(title: "Review tab dedupe")
        await store.begin(written, in: repository)

        open.publish([report(written.id, title: nil, state: .paused)], focused: nil)

        #expect(open.sessions.first?.title == "Review tab dedupe")
    }

    /// A tab restored before its repository's file was read takes the title
    /// written down from the next report after the file is read.
    @Test func aTabRestoredBeforeItsFileIsReadTakesItsRecordsTitle() async {
        let first = AgentSessions(state: state, clock: clock, launchedAt: launch)
        let old = session(title: "Review tab dedupe")
        await first.begin(old, in: repository)
        await first.flushSaves()

        let open = WindowAgentSessions(store: store)
        open.publish([report(old.id, title: nil, state: .paused)], focused: old.id)
        #expect(open.sessions.first?.title == "Claude Code")

        await store.load(repository)
        open.publish([report(old.id, title: nil, state: .paused)], focused: old.id)

        #expect(open.sessions.first?.title == "Review tab dedupe")
        #expect(open.sessions.first?.state == .paused)
    }

    /// Another window's tab is not a crash's leftover, though this window
    /// never claimed it.
    @Test func aSessionOpenInAnotherWindowIsNotEndedAsAnOrphan() async {
        var old = session()
        old.startedAt = launch.addingTimeInterval(-5000)
        old.lastSeenAt = launch.addingTimeInterval(-4000)
        await store.begin(old, in: repository)
        WindowAgentSessions(store: store).publish([report(old.id, state: .paused)], focused: nil)

        await store.reconcile(WorkspaceID(main), in: repository, claimed: [])

        #expect(store.session(old.id)?.endedAt == nil)
    }

    @Test func whatATabSaysIsNotWrittenDown() async throws {
        let open = WindowAgentSessions(store: store)
        let written = session()
        open.publish([report(written.id, state: .working)], focused: written.id)
        await store.begin(written, in: repository)
        await store.flushSaves()

        let stored = try #require(
            await state.load(SessionHistorySnapshot.self, forKey: SessionHistorySnapshot.persistenceKey(for: repository))
        )
        #expect(stored.records.map(\.live) == [nil])
    }
}
