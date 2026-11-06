import Foundation

/// The app's own state that belongs to no window, as it goes to ``StateStore``.
///
/// The repositories the user has adopted, and an index of the windows that
/// have state worth keeping. Nothing window-shaped lives here beyond that
/// index: which workspace a window shows, which it keeps open and which
/// repositories it lists are its own, in a ``WindowSnapshot``. If something
/// about a window ends up in this struct, the split has not held.
public struct AppSnapshot: Codable, Sendable, Equatable {
    /// Where this snapshot is stored. One key for the whole app.
    public static let persistenceKey = "app"

    public var version = 1

    /// The folders the user has adopted, whichever windows list them.
    ///
    /// The only thing Herder persists that the user would have to recreate by
    /// hand, because each one carries a security-scoped bookmark. Nothing here
    /// may drop them — see ``AppSnapshotStore``, which reads this key before
    /// writing it for that reason.
    public var repositories: [Repository]

    /// The windows that have a ``WindowSnapshot``, most recently shown first.
    ///
    /// An index and not the snapshots themselves, so that one window saving
    /// does not rewrite the others, and so a snapshot whose window is gone can
    /// be found and swept. The order is what lets a window with nothing of its
    /// own to restore adopt the one the user last used.
    public var windows: [UUID]

    public init(repositories: [Repository] = [], windows: [UUID] = []) {
        self.repositories = repositories
        self.windows = windows
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        repositories = try container.decodeIfPresent([Repository].self, forKey: .repositories) ?? []
        windows = try container.decodeIfPresent([UUID].self, forKey: .windows) ?? []
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
