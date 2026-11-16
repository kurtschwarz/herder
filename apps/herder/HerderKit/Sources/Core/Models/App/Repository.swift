import Foundation

/// A folder on disk the user has adopted, one to one.
///
/// The record of the folder and nothing about where it sits. Which windows list
/// it, in what order and whether it is folded are each window's own, in a
/// ``RepositoryMembership``: the same record can be in several sidebars at once,
/// arranged differently in each, and the bookmark behind it exists exactly once.
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

    /// When it was adopted. The order the pool is kept in.
    public var addedAt: Date

    /// Whether the folder could be reached. Not persisted: an unmounted volume
    /// is a fact about right now, not about the repository, and a stored `false`
    /// would outlive plugging the drive back in.
    public var isAvailable: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        bookmark: Data,
        addedAt: Date = .now,
        isAvailable: Bool = true
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmark = bookmark
        self.addedAt = addedAt
        self.isAvailable = isAvailable
    }

    public var url: URL { URL(filePath: path) }

    /// ``isAvailable`` is deliberately absent: it is about the present moment.
    /// Everything else is what the user would have to recreate by hand. A record
    /// written when the sidebar's arrangement lived here still decodes: the
    /// keys it carried that no longer exist are ignored.
    private enum CodingKeys: String, CodingKey {
        case id, name, path, bookmark, addedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        bookmark = try container.decode(Data.self, forKey: .bookmark)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        // Decided by resolving the bookmark at load, not by what was written.
        isAvailable = true
    }
}
