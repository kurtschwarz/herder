import Core
import Foundation

/// Whether the terminal panel is open, and how tall, for one workspace.
///
/// All that is remembered: a process cannot be brought back, so an open panel
/// comes back with one fresh shell, and nothing about the tabs, their
/// scrollback or their directories is kept.
///
/// `height` is `nil` until the panel has been dragged, so changing the default
/// later moves everyone who never chose one; see ``PanelHeight``.
///
/// Not `@Observable`, like ``EditorUIState``: the model mirrors what is drawn.
final class TerminalUIState: PersistedWorkspaceUIState {
    /// What is on disk, so it is never renamed without a migration.
    static let persistenceKey = "terminal.panel"

    var isOpen = false
    var height: CGFloat?

    init() {}

    private struct Stored: Codable {
        var isOpen: Bool?
        var height: Double?

        init(isOpen: Bool, height: Double?) {
            self.isOpen = isOpen
            self.height = height
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            isOpen = try container.decodeIfPresent(Bool.self, forKey: .isOpen)
            height = try container.decodeIfPresent(Double.self, forKey: .height)
        }
    }

    func encode() throws -> Data {
        try JSONEncoder().encode(Stored(isOpen: isOpen, height: height.map(Double.init)))
    }

    func restore(from data: Data) throws {
        let stored = try JSONDecoder().decode(Stored.self, from: data)
        isOpen = stored.isOpen ?? false
        height = stored.height.map { CGFloat($0) }
    }
}
