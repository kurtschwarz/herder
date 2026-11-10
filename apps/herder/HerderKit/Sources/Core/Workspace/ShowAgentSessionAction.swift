import Foundation

/// Asks for an open agent session to be brought forward: its worktree shown,
/// its tab in front, and the keyboard in it.
///
/// For the sidebar's list of sessions, which cannot reach the agent panel
/// itself. Shaped like ``StartAgentSessionAction``, and carried the same way.
@MainActor
public struct ShowAgentSessionAction {
    private let handler: (AgentSession) -> Void

    public init(_ handler: @escaping (AgentSession) -> Void) {
        self.handler = handler
    }

    public func callAsFunction(_ session: AgentSession) {
        handler(session)
    }
}

extension ShowAgentSessionAction {
    /// Does nothing, so a feature drawn without a window around it still
    /// builds.
    public static let inert = ShowAgentSessionAction { _ in }
}
