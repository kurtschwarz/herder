import Foundation

/// A tab with a process running in it, as far as the process list is
/// concerned: whose process is it, and what should it be called.
///
/// A plain value, read out of the `RunningProcesses` registry at the moment of
/// a refresh, so that deciding which processes belong to which tab is pure.
public struct ProcessOwner: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case agentSession
        case terminal
    }

    /// The tab's id: the session's for an agent, the shell's for a terminal.
    public var id: UUID
    public var kind: Kind
    public var window: UUID
    public var worktree: WorkspaceID
    public var branch: String?
    public var title: String

    /// The process the tab started. `nil` once it has ended and the tab has
    /// not yet been closed.
    public var pid: Int32?

    /// What the agent is doing, read the way the sidebar reads it. `nil` for a
    /// terminal.
    public var state: AgentSession.State?

    public init(
        id: UUID,
        kind: Kind,
        window: UUID = UUID(),
        worktree: WorkspaceID,
        branch: String? = nil,
        title: String,
        pid: Int32?,
        state: AgentSession.State? = nil
    ) {
        self.id = id
        self.kind = kind
        self.window = window
        self.worktree = worktree
        self.branch = branch
        self.title = title
        self.pid = pid
        self.state = state
    }
}
