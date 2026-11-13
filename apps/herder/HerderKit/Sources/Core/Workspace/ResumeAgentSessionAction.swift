import Foundation

/// Asks for a session from the history to be picked up again: a worktree
/// shown, which is the one it ran in unless that is gone, and the agent
/// resumed in a tab of its own.
///
/// For the sidebar's history, which cannot reach the agent panel itself.
/// Shaped like ``ShowAgentSessionAction``, and carried the same way.
@MainActor
public struct ResumeAgentSessionAction {
    private let handler: (AgentSession, WorkspaceID) -> Void

    public init(_ handler: @escaping (AgentSession, WorkspaceID) -> Void) {
        self.handler = handler
    }

    public func callAsFunction(_ record: AgentSession, in worktree: WorkspaceID) {
        handler(record, worktree)
    }
}

extension ResumeAgentSessionAction {
    /// Does nothing, so a feature drawn without a window around it still
    /// builds.
    public static let inert = ResumeAgentSessionAction { _, _ in }
}
