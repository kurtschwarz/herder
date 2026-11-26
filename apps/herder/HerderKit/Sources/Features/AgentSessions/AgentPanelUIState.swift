import Core
import Foundation

/// The agent sessions open in one workspace's panel, and which was in front.
///
/// Each is remembered with its id and a copy of the agent it runs, so it is
/// resumed with the command it was started with even if the agent has since
/// been edited or removed in Settings. The processes are not remembered: a tab
/// comes back paused and resumes when it is shown. What an agent keeps of the
/// session itself, it keeps.
///
/// Not `@Observable`, like ``TerminalUIState``: the model mirrors what is drawn.
final class AgentPanelUIState: PersistedWorkspaceUIState {
    /// What is on disk, so it is never renamed without a migration. It held
    /// whether the panel was open, once; that field is no longer read.
    static let persistenceKey = "agents.panel"

    /// A `pinned` field written by an earlier build is skipped when decoding,
    /// and not written again.
    struct Tab: Codable, Equatable {
        var id: UUID
        var agent: Agent
        var number: Int
        /// Absent in a tab saved before there were modes, which is build.
        var mode: SessionMode?
        /// What the person named the tab, if anything.
        var name: String?
        /// The agent's own id for the session, once looked up.
        var session: String?
        var started: Date?
        /// The GitHub issue it was started from, if it was. Absent in a tab
        /// saved before there were any.
        var issue: LinkedIssue?
    }

    var tabs: [Tab] = []
    var active: UUID?

    init() {}

    private struct Stored: Codable {
        var tabs: [Tab]?
        var active: UUID?
    }

    func encode() throws -> Data {
        try JSONEncoder().encode(Stored(tabs: tabs, active: active))
    }

    func restore(from data: Data) throws {
        let stored = try JSONDecoder().decode(Stored.self, from: data)
        tabs = stored.tabs ?? []
        active = stored.active
    }
}
