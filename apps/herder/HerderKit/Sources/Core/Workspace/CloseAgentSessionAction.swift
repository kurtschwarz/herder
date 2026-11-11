import Foundation

/// Asks for an open agent session to be closed: its terminal UI ended and its
/// tab taken away, as closing the tab itself would.
///
/// For the sidebar's list of sessions, which cannot reach the agent panel
/// itself. Shaped like ``RenameAgentSessionAction``, and carried the same way.
@MainActor
public struct CloseAgentSessionAction {
    private let handler: (AgentSession) -> Void

    public init(_ handler: @escaping (AgentSession) -> Void) {
        self.handler = handler
    }

    public func callAsFunction(_ session: AgentSession) {
        handler(session)
    }
}

extension CloseAgentSessionAction {
    /// Does nothing, so a feature drawn without a window around it still
    /// builds.
    public static let inert = CloseAgentSessionAction { _ in }
}
