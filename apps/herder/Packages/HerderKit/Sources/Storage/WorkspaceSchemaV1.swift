import Foundation
import SwiftData

/// Version 1 of the workspace store.
///
/// The schema is versioned from the first release so the first migration can be
/// written against a schema that has a name, rather than against whatever shape
/// happened to ship.
public enum WorkspaceSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] { [Workspace.self] }

    /// A folder on disk the user has adopted, one to one.
    ///
    /// **The rest of the codebase calls this `Repository`**, through the
    /// typealias below. The class keeps the name `Workspace` because the class
    /// name *is* the stored entity name: SwiftData derives the SQLite table from
    /// it, and the store on disk has a `ZWORKSPACE` table recorded against a
    /// schema that says `Workspace`. Renaming the class renames the entity,
    /// which makes the existing store an unknown model version and leaves the
    /// user's adopted folders — and their security-scoped bookmarks, which
    /// cannot be regenerated — unreadable.
    ///
    /// So the persisted name stays until the model is retired for snapshots in
    /// Phase 4e, at which point the question disappears with it. Do not rename
    /// this class to match the vocabulary; rename nothing here at all.
    @Model
    public final class Workspace {
        /// Stable for the lifetime of the row. Folders move and get renamed, so
        /// nothing downstream — ordering, selection, sessions — keys off the path.
        @Attribute(.unique) public var id: UUID

        /// Shown in the sidebar. Defaults to the folder's name when the workspace
        /// is added, and is the user's to change after that. It deliberately does
        /// not follow a later rename of the folder.
        public var name: String

        /// Where the folder was when it was last resolved. A cache, for display
        /// and for rejecting a folder that is already open: `bookmark` is the
        /// handle that actually reopens it.
        public var path: String

        /// Security-scoped bookmark: the sandbox's standing permission to reopen
        /// this folder on a later launch. See `BookmarkClient`.
        public var bookmark: Data

        /// Position in the sidebar. Renumbered across every row on reorder.
        public var order: Int

        /// Tiebreaker for equal `order`, and the natural sort before the user has
        /// ever reordered anything.
        public var addedAt: Date

        /// Whether the folder could be reached at launch. Not stored: an
        /// unmounted volume is a fact about right now, not about the workspace.
        @Transient public var isAvailable: Bool = true

        public init(
            id: UUID = UUID(),
            name: String,
            path: String,
            bookmark: Data,
            order: Int,
            addedAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.path = path
            self.bookmark = bookmark
            self.order = order
            self.addedAt = addedAt
        }
    }
}

/// What everything outside this file calls it.
///
/// The name the architecture uses, over the name the store recorded. See the
/// class above for why the two differ. Unchanged in V2, which carries it over
/// rather than redeclaring it.
public typealias Repository = WorkspaceSchemaV1.Workspace
