import Foundation

/// Asks for an open agent session to be named: what its tab is called, and
/// what the sidebar and the history call it.
///
/// For the sidebar's list of sessions, which cannot reach the agent panel
/// itself. Shaped like ``ShowAgentSessionAction``, and carried the same way.
@MainActor
public struct RenameAgentSessionAction {
    private let handler: (AgentSession, String) -> Void

    public init(_ handler: @escaping (AgentSession, String) -> Void) {
        self.handler = handler
    }

    public func callAsFunction(_ session: AgentSession, to name: String) {
        handler(session, name)
    }
}

extension RenameAgentSessionAction {
    /// Does nothing, so a feature drawn without a window around it still
    /// builds.
    public static let inert = RenameAgentSessionAction { _, _ in }
}
