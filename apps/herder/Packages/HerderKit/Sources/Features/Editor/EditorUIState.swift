import Core
import Foundation

/// Which file the editor has open, for one workspace.
///
/// On the workspace rather than in the model for the same reason as the file
/// tree's expansion: the model is shared by every window, and what was open is
/// something the user did to a particular checkout.
///
/// Not `@Observable`: nothing draws from it. The model reads it when a
/// workspace comes forward and writes it when a file is opened.
///
/// `internal`: `Core` holds this without knowing the type.
final class EditorUIState: PersistedWorkspaceUIState {
    /// What is on disk, so it is never renamed without a migration.
    static let persistenceKey = "editor.openFile"

    /// The file last opened. Kept when the file goes from disk: the pane shows
    /// it struck through, and only opening something else forgets it.
    var file: PathKey?

    init() {}

    /// A struct rather than a bare path, so more than one file can arrive as a
    /// second field instead of a second key.
    private struct Stored: Codable {
        var file: String?

        init(file: String?) {
            self.file = file
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            file = try container.decodeIfPresent(String.self, forKey: .file)
        }
    }

    /// As a path, not a `PathKey`: see ``FileTreeUIState`` for why `PathKey`
    /// is not `Codable`. Canonical when written, so it comes back through
    /// `init(canonical:)`.
    func encode() throws -> Data {
        try JSONEncoder().encode(Stored(file: file?.path))
    }

    func restore(from data: Data) throws {
        file = try JSONDecoder().decode(Stored.self, from: data).file.map(PathKey.init(canonical:))
    }
}
