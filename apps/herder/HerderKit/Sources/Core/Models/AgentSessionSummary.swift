import Foundation

/// One agent session open in a window, as a list beside the agent panel
/// shows it: what it is called, where it runs, and what it is doing.
///
/// Herder does not talk to agents. What it knows is what any terminal knows:
/// the title the program gave itself, the status it reports (OSC 7501), and
/// whether it has exited.
public struct AgentSessionSummary: Sendable, Equatable, Identifiable {
    public enum State: Sendable, Equatable {
        /// Remembered from before, and not yet picked up again: it resumes
        /// when its tab is shown.
        case paused
        case starting
        /// Reported working.
        case working
        /// Reported blocked on the person, with what it said.
        case needsInput(String?)
        /// Reported nothing that needs anyone, or nothing at all.
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
