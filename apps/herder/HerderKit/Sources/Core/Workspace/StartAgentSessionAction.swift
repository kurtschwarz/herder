import Foundation

/// Asks for a new agent session to be started in a worktree, in this window's
/// agent panel.
///
/// The sidebar is where a person points at a worktree and the agent panel is
/// where the session runs, and they are two features that may not see each
/// other. So the sidebar says which worktree through this, and the App target,
/// which sees both, switches to it, opens the panel and starts the session.
///
/// Shaped like ``OpenWorkspaceAction``, and carried the same way: its
/// environment key is in `DesignSystem`.
@MainActor
public struct StartAgentSessionAction {
    private let handler: (WorkspaceID) -> Void

    public init(_ handler: @escaping (WorkspaceID) -> Void) {
        self.handler = handler
    }

    public func callAsFunction(_ workspace: WorkspaceID) {
        handler(workspace)
    }
}

extension StartAgentSessionAction {
    /// Does nothing, so a feature drawn without a window around it still
    /// builds.
    public static let inert = StartAgentSessionAction { _ in }
}
