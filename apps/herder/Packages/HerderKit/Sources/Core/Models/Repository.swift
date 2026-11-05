import Foundation

/// A folder on disk the user has adopted, one to one.
///
/// A value type, held by ``RepositoryStore``. It used to be a SwiftData
/// `@Model`, which meant a reference the views mutated directly and a `@Query`
/// to see the list; now the store owns the array and Observation does what
/// `@Query` did.
public struct Repository: Identifiable, Sendable, Codable, Equatable {
    /// Stable for the lifetime of the record. Folders move and get renamed, so
    /// nothing downstream — ordering, selection, sessions — keys off the path.
    public var id: UUID

    /// Shown in the sidebar. Defaults to the folder's name when the repository
    /// is added, and is the user's to change after that. It deliberately does
    /// not follow a later rename of the folder.
    public var name: String

    /// Where the folder was when it was last resolved. A cache, for display and
    /// for rejecting a folder that is already adopted: ``bookmark`` is the
    /// handle that actually reopens it.
    public var path: String

    /// Security-scoped bookmark: the sandbox's standing permission to reopen
    /// this folder on a later launch. See ``BookmarkClient``.
    ///
    /// The one piece of state in Herder that cannot be rebuilt from disk or
    /// git. Regenerating it means asking the user to find the folder again in
    /// an open panel, so nothing may drop it.
    public var bookmark: Data

    /// Position in the sidebar. Renumbered across every row on reorder.
    public var order: Int

    /// Tiebreaker for equal ``order``, and the natural sort before the user has
    /// ever reordered anything.
    public var addedAt: Date

    /// Whether the sidebar is hiding this repository's worktrees.
    ///
    /// View state kept on the record, like ``order``, and for the same reason:
    /// it is about this repository, there is one sidebar, and it is worth
    /// remembering across launches. Folded rather than unfolded, so a
    /// repository the user has never touched — and one added later — starts
    /// open.
    public var isCollapsed: Bool

    /// Whether the folder could be reached. Not persisted: an unmounted volume
    /// is a fact about right now, not about the repository, and a stored `false`
    /// would outlive plugging the drive back in.
    public var isAvailable: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        bookmark: Data,
        order: Int,
        addedAt: Date = .now,
        isCollapsed: Bool = false,
        isAvailable: Bool = true
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmark = bookmark
        self.order = order
        self.addedAt = addedAt
        self.isCollapsed = isCollapsed
        self.isAvailable = isAvailable
    }

    public var url: URL { URL(filePath: path) }

    /// ``isAvailable`` is deliberately absent: it is about the present moment.
    /// Everything else is what the user would have to recreate by hand.
    private enum CodingKeys: String, CodingKey {
        case id, name, path, bookmark, order, addedAt, isCollapsed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        bookmark = try container.decode(Data.self, forKey: .bookmark)
        order = try container.decode(Int.self, forKey: .order)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        // Added after the first repositories were written, so absent state
        // means open rather than meaning anything.
        isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        // Decided by resolving the bookmark at load, not by what was written.
        isAvailable = true
    }
}
