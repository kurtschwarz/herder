import Foundation

/// Asks for a new agent session to be started in a worktree, in this window's
/// agent panel, with a given agent or with whichever was used last, in plan or build mode.
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
    private let handler: (WorkspaceID, Agent?, SessionMode, String?, String?, LinkedIssue?) -> Void

    public init(_ handler: @escaping (WorkspaceID, Agent?, SessionMode, String?, String?, LinkedIssue?) -> Void) {
        self.handler = handler
    }

    /// `agent` is `nil` for the one used last. `prompt` is the session's first
    /// message, for an agent that can be given one, and `name` is what the
    /// session is called in the sidebar, in place of the agent's. `issue` is
    /// the GitHub issue it is started from, which the session remembers.
    public func callAsFunction(
        _ workspace: WorkspaceID,
        agent: Agent? = nil,
        mode: SessionMode = .build,
        prompt: String? = nil,
        name: String? = nil,
        issue: LinkedIssue? = nil
    ) {
        handler(workspace, agent, mode, prompt, name, issue)
    }
}

extension StartAgentSessionAction {
    /// Does nothing, so a feature drawn without a window around it still
    /// builds.
    public static let inert = StartAgentSessionAction { _, _, _, _, _, _ in }
}
