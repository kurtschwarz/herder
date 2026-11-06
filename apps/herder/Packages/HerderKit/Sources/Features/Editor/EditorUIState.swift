import Core
import Foundation

/// Which files the editor has open, for one workspace.
///
/// On the workspace rather than in the model for the same reason as the file
/// tree's expansion: the model is shared by every window, and what was open is
/// something the user did to a particular checkout.
///
/// Not `@Observable`: nothing draws from it. The model reads it when a
/// workspace comes forward and writes it when a tab is opened or closed.
///
/// `internal`: `Core` holds this without knowing the type.
final class EditorUIState: PersistedWorkspaceUIState {
    /// What is on disk, so it is never renamed without a migration. It says
    /// `openFile` because that is what it held when it was written, and a key
    /// is a file name on the user's disk: the tabs arrived as fields inside
    /// it, which is the shape ``Stored`` was given for exactly this.
    static let persistenceKey = "editor.openFile"

    /// The files with a tab, in the order they were opened. Kept when a file
    /// goes from disk: the tab shows it struck through, and only closing it
    /// forgets it.
    var files: [PathKey] = []

    /// Which of ``files`` was showing.
    var active: PathKey?

    init() {}

    /// A struct rather than a bare path, so more than one file can arrive as a
    /// second field instead of a second key — which is what happened.
    private struct Stored: Codable {
        /// Written by the builds that could only open one file at a time.
        /// Read, never written: a saved `file` becomes a single tab.
        var file: String?
        var files: [String]?
        var active: String?

        init(files: [String], active: String?) {
            self.files = files
            self.active = active
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            file = try container.decodeIfPresent(String.self, forKey: .file)
            files = try container.decodeIfPresent([String].self, forKey: .files)
            active = try container.decodeIfPresent(String.self, forKey: .active)
        }
    }

    /// As paths, not `PathKey`s: see ``FileTreeUIState`` for why `PathKey`
    /// is not `Codable`. Canonical when written, so they come back through
    /// `init(canonical:)`.
    func encode() throws -> Data {
        try JSONEncoder().encode(Stored(files: files.map(\.path), active: active?.path))
    }

    func restore(from data: Data) throws {
        let stored = try JSONDecoder().decode(Stored.self, from: data)
        if let list = stored.files {
            files = list.map(PathKey.init(canonical:))
            active = stored.active.map(PathKey.init(canonical:))
        } else {
            // Written before there were tabs: the one file is the one tab.
            files = stored.file.map { [PathKey(canonical: $0)] } ?? []
            active = files.first
        }
    }
}
