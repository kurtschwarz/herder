import Foundation
import Observation

/// The agent sessions open in one window, for the sidebar to list.
///
/// Per window, like the agent panel whose sessions these are: two windows on
/// one checkout run their own. The panel writes it and the sidebar reads it,
/// which is how two features that cannot see each other share what is open.
///
/// The annotation is explicit because `Core` keeps the nonisolated default.
@MainActor
@Observable
public final class OpenAgentSessions {
    public private(set) var sessions: [AgentSessionSummary] = []

    /// The session in front in the panel, for the workspace showing.
    public private(set) var focused: UUID?

    public init() {}

    /// The sessions running in `workspace`, in the order they were opened.
    public func sessions(in workspace: WorkspaceID) -> [AgentSessionSummary] {
        sessions.filter { $0.workspace == workspace }
    }

    /// Replaces what is listed. Only when something changed, so a panel that
    /// says the same thing every second redraws nothing.
    public func update(_ sessions: [AgentSessionSummary], focused: UUID?) {
        if self.sessions != sessions { self.sessions = sessions }
        if self.focused != focused { self.focused = focused }
    }
}
