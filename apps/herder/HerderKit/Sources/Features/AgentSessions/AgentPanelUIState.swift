import Core
import Foundation

/// Whether the agent panel is open for one workspace.
///
/// All that is remembered: an agent's terminal UI is a process and cannot be
/// brought back, so an open panel comes back with one fresh session of the
/// agent used last, and nothing about the tabs is kept. What an agent keeps of
/// its own sessions, it keeps: an older one is resumed from inside its
/// terminal UI.
///
/// The panel's width is not here. That is a choice about the window's layout,
/// so it is the window's, with the other pane widths.
///
/// Not `@Observable`, like ``TerminalUIState``: the model mirrors what is drawn.
final class AgentPanelUIState: PersistedWorkspaceUIState {
    /// What is on disk, so it is never renamed without a migration.
    static let persistenceKey = "agents.panel"

    var isOpen = false

    init() {}

    private struct Stored: Codable {
        var isOpen: Bool?
    }

    func encode() throws -> Data {
        try JSONEncoder().encode(Stored(isOpen: isOpen))
    }

    func restore(from data: Data) throws {
        isOpen = try JSONDecoder().decode(Stored.self, from: data).isOpen ?? false
    }
}
