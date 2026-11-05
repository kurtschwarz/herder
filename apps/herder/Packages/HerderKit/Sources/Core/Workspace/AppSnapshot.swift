import Foundation

/// The app's own state across every window, as it goes to ``StateStore``.
///
/// Which workspaces were open, so a relaunch can reopen them. **Not** which
/// window was showing which: that is per-window and `@SceneStorage` already
/// restores it, scene by scene, without this having to model windows at all.
///
/// The adopted repositories are not here yet — they are still SwiftData rows,
/// and move in 4e. When they do, they arrive as a new field with an empty
/// default, like everything else.
public struct AppSnapshot: Codable, Sendable, Equatable {
    /// Where this snapshot is stored. One key for the whole app.
    public static let persistenceKey = "app"

    public var version = 1

    /// Workspaces that were open when the app last saved, in the order they
    /// were opened. Order is kept because reopening in a different one would
    /// shuffle the sidebar for no reason the user caused.
    public var openWorkspaces: [WorkspaceID]

    public init(openWorkspaces: [WorkspaceID] = []) {
        self.openWorkspaces = openWorkspaces
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        openWorkspaces = try container.decodeIfPresent([WorkspaceID].self, forKey: .openWorkspaces) ?? []
    }
}

extension WorkspaceSnapshot {
    /// Where a workspace's snapshot is stored. One key each, so saving one does
    /// not rewrite the rest — and so the file layout Phase 7 moves to
    /// (`workspaces/<id>.json`) falls out of the keys rather than needing a
    /// scheme of its own.
    public static func persistenceKey(for id: WorkspaceID) -> String {
        "workspace:\(id.root.path)"
    }

    public var persistenceKey: String {
        Self.persistenceKey(for: id)
    }
}
