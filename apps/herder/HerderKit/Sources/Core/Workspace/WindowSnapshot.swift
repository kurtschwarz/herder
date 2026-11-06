import Foundation

/// One window, as it goes to ``StateStore``.
///
/// What a window needs to come back as it was: the repositories it lists, the
/// workspaces it keeps open and the one it shows. A plain struct for the same reason as ``WorkspaceSnapshot``,
/// and decoded the same way: every field but the identity has a default, which
/// is the whole migration strategy.
///
/// Not here: how recently the window was used. That is its position in
/// ``AppSnapshot/windows``, and saying it twice would give two answers.
public struct WindowSnapshot: Codable, Sendable, Equatable {
    public var version = 1

    /// Names the window across launches. Minted once, when the window first
    /// appears, and kept in its scene storage.
    public var id: UUID

    /// The workspaces this window keeps warm, in the order they were opened.
    /// A workspace lives while any window names it here — see
    /// ``WorkspaceRegistry/open(_:holder:)``.
    public var openWorkspaces: [WorkspaceID]

    /// The one on screen. Always one of ``openWorkspaces`` when present.
    public var activeWorkspace: WorkspaceID?

    /// The repositories this window lists, in its order, each with whether it
    /// is folded here. Records only by id: the folder, its name and its
    /// bookmark are the app's, in ``AppSnapshot/repositories``.
    public var repositories: [RepositoryMembership]

    /// How wide the window's outer panes were left. Not part of ``isBlank``: a
    /// pane dragged in a window with nothing in it is not worth adopting.
    public var paneWidths: PaneWidths

    public init(
        id: UUID,
        openWorkspaces: [WorkspaceID] = [],
        activeWorkspace: WorkspaceID? = nil,
        repositories: [RepositoryMembership] = [],
        paneWidths: PaneWidths = PaneWidths()
    ) {
        self.id = id
        self.openWorkspaces = openWorkspaces
        self.activeWorkspace = activeWorkspace
        self.repositories = repositories
        self.paneWidths = paneWidths
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        id = try container.decode(UUID.self, forKey: .id)
        openWorkspaces = try container.decodeIfPresent([WorkspaceID].self, forKey: .openWorkspaces) ?? []
        activeWorkspace = try container.decodeIfPresent(WorkspaceID.self, forKey: .activeWorkspace)
        repositories = try container.decodeIfPresent([RepositoryMembership].self, forKey: .repositories) ?? []
        paneWidths = try container.decodeIfPresent(PaneWidths.self, forKey: .paneWidths) ?? PaneWidths()
    }

    /// Where a window's snapshot is stored. One key each.
    public static func persistenceKey(for id: UUID) -> String {
        "window:\(id.uuidString)"
    }

    public var persistenceKey: String {
        Self.persistenceKey(for: id)
    }

    /// Whether there is nothing here worth a file. A window nobody has done
    /// anything in is not worth remembering, and would otherwise be the one a
    /// relaunch adopts.
    public var isBlank: Bool {
        openWorkspaces.isEmpty && activeWorkspace == nil && repositories.isEmpty
    }
}
