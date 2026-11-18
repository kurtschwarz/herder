import Foundation

/// Asks for an open agent session to be brought forward: its worktree shown,
/// its tab in front, and the keyboard in it.
///
/// For the sidebar's list of sessions, which cannot reach the agent panel
/// itself. Shaped like ``StartAgentSessionAction``, and carried the same way.
@MainActor
public struct ShowAgentSessionAction {
    private let handler: (AgentSession, Bool) -> Void

    public init(_ handler: @escaping (AgentSession, Bool) -> Void) {
        self.handler = handler
    }

    /// `takingFocus` is whether the keyboard goes to the session's terminal.
    /// Not for the editor's selection prompt, which shows the session it
    /// wrote to and leaves the person where they were.
    public func callAsFunction(_ session: AgentSession, takingFocus: Bool = true) {
        handler(session, takingFocus)
    }
}

extension ShowAgentSessionAction {
    /// Does nothing, so a feature drawn without a window around it still
    /// builds.
    public static let inert = ShowAgentSessionAction { _, _ in }
}
