import Foundation

/// The app's own state across every window, as it goes to ``StateStore``.
///
/// The repositories the user has adopted, and which workspaces were open so a
/// relaunch can reopen them. **Not** which window was showing which: that is
/// per-window and `@SceneStorage` already restores it, scene by scene, without
/// this having to model windows at all.
public struct AppSnapshot: Codable, Sendable, Equatable {
    /// Where this snapshot is stored. One key for the whole app.
    public static let persistenceKey = "app"

    public var version = 1

    /// Workspaces that were open when the app last saved, in the order they
    /// were opened. Order is kept because reopening in a different one would
    /// shuffle the sidebar for no reason the user caused.
    public var openWorkspaces: [WorkspaceID]

    /// The folders the user has adopted, in sidebar order.
    ///
    /// The only thing Herder persists that the user would have to recreate by
    /// hand, because each one carries a security-scoped bookmark. Nothing here
    /// may drop them — see `RepositoryStore.save()`, which reads this key before
    /// writing it for that reason.
    public var repositories: [Repository]

    /// The workspace most recently shown by any window, for a window that has
    /// nothing of its own to restore. `@SceneStorage` is the per-window record
    /// but only comes back when the system restores the scene; this is what
    /// covers quitting with the windows closed.
    public var lastActiveWorkspace: WorkspaceID?

    public init(
        openWorkspaces: [WorkspaceID] = [],
        repositories: [Repository] = [],
        lastActiveWorkspace: WorkspaceID? = nil
    ) {
        self.openWorkspaces = openWorkspaces
        self.repositories = repositories
        self.lastActiveWorkspace = lastActiveWorkspace
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        openWorkspaces = try container.decodeIfPresent([WorkspaceID].self, forKey: .openWorkspaces) ?? []
        repositories = try container.decodeIfPresent([Repository].self, forKey: .repositories) ?? []
        lastActiveWorkspace = try container.decodeIfPresent(WorkspaceID.self, forKey: .lastActiveWorkspace)
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
