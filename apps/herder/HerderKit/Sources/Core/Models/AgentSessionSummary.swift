import Foundation

/// One agent session open in a window, as a list beside the agent panel
/// shows it: what it is called, where it runs, and what it seems to be doing.
///
/// "Seems", because Herder does not talk to agents. What it knows is what any
/// terminal knows: the title the program gave itself, whether it is writing,
/// whether it asked for a notification since the person last typed, and
/// whether it has exited.
public struct AgentSessionSummary: Sendable, Equatable, Identifiable {
    public enum State: Sendable, Equatable {
        case starting
        /// Writing to its terminal, or reporting progress.
        case working
        /// Asked for attention, with what it said, and has not been answered.
        case needsInput(String?)
        /// Quiet: waiting for the next prompt, as far as can be told.
        case idle
        /// The terminal UI exited with this status.
        case exited(Int32)
        /// It could not be started.
        case failed
    }

    public let id: UUID
    public var workspace: WorkspaceID

    /// What the program called itself, or the agent's name until it does.
    public var title: String
    public var agentName: String
    public var state: State

    /// When it last wrote anything, or started.
    public var lastActivity: Date

    public init(
        id: UUID,
        workspace: WorkspaceID,
        title: String,
        agentName: String,
        state: State,
        lastActivity: Date
    ) {
        self.id = id
        self.workspace = workspace
        self.title = title
        self.agentName = agentName
        self.state = state
        self.lastActivity = lastActivity
    }
}
