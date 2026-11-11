import Foundation
import Observation

/// The agent sessions open in one window, and what each is doing: what that
/// window's sidebar lists under "Working & waiting".
///
/// Per window, like the agent panel whose tabs these are: two windows on one
/// checkout run their own sessions, and each lists only its own. The panel
/// writes it and the sidebar reads it, which is how two features that cannot
/// see each other share what is open.
///
/// Each is an ``AgentSession`` with its ``AgentSession/live`` part: the record
/// from ``store`` where there is one, and what the tab says over it. What the
/// tab says changes every second while an agent works, which is why it lives
/// here, where it redraws this window and no other, and not in the app-wide
/// store. What is worth keeping of it goes on to the store as it is reported.
///
/// The annotation is explicit because `Core` keeps the nonisolated default.
@MainActor
@Observable
public final class WindowAgentSessions {
    /// Every session there has been, app-wide. Told what this window's tabs
    /// say, and where a session is written down, started, ended and resumed.
    public let store: AgentSessions

    /// The window these are open in.
    public let window: UUID

    /// In the order the panel lists them. Includes an ended session whose tab
    /// is open to be read; the sidebar lists that one under Closed instead.
    public private(set) var sessions: [AgentSession] = []

    /// Most recently active first, for the sidebar; ``sessions`` keeps the
    /// panel's order. Sessions active at the same moment go newest start
    /// first, and after that stay in the panel's order.
    public var sessionsByRecency: [AgentSession] {
        sessions.enumerated().filter { !$0.element.isEnded }.sorted { lhs, rhs in
            let (a, b) = (lhs.element, rhs.element)
            let (activeA, activeB) = (a.live?.lastActivity ?? a.lastSeenAt, b.live?.lastActivity ?? b.lastSeenAt)
            if activeA != activeB { return activeA > activeB }
            if a.startedAt != b.startedAt { return a.startedAt > b.startedAt }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// The session in front in the panel, for the workspace showing.
    public private(set) var focused: UUID?

    public init(store: AgentSessions, window: UUID = UUID()) {
        self.store = store
        self.window = window
    }

    /// The sessions open in `workspace`, in the order they were opened. An
    /// ended one with a tab open is being read, not worked in: it is left out.
    public func sessions(in workspace: WorkspaceID) -> [AgentSession] {
        sessions.filter { $0.worktree == workspace && !$0.isEnded }
    }

    /// Replaces what is open with `reports`, in that order, and which is in
    /// front. Passes them on to ``store`` first, so a session written down
    /// is listed with the title it has there. Assigns only what changed, so a
    /// panel that says the same thing every second redraws nothing.
    public func publish(_ reports: [AgentSessions.Report], focused: UUID?, at now: Date = .now) {
        store.note(reports, window: window, at: now)
        let before = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let next = reports.map { report in
            // Written down, else as this window last had it, else new: a tab
            // whose agent has not run yet is this window's alone.
            var session = store.session(report.id) ?? before[report.id]?.record ?? AgentSession(
                id: report.id,
                agentID: report.agentID,
                agentName: report.agentName,
                worktree: report.worktree,
                title: report.title ?? report.fallbackTitle,
                startedAt: now
            )
            if let title = report.title { session.title = title }
            session.name = report.name
            if let sessionID = report.sessionID { session.sessionID = sessionID }
            // A tab not yet run this launch is as active as its record last
            // saw it, else as it was started, else not at all.
            let activity = report.lastActivity
                ?? store.session(report.id)?.lastSeenAt
                ?? report.startedAt
                ?? .distantPast
            session.live = AgentSession.Live(state: report.state, lastActivity: activity)
            return session
        }
        if sessions != next { sessions = next }
        if self.focused != focused { self.focused = focused }
    }
}
