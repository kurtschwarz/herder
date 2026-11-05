import Foundation
import SwiftData

/// Version 2 of the workspace store: adds ``StoredState``.
///
/// ``Repository`` is carried over from ``WorkspaceSchemaV1`` unchanged rather
/// than redeclared. A version that redeclares a model it has not altered gives
/// two classes the same table and nothing to tell them apart; the version
/// identifier is what records that the schema moved, and the stage below is
/// what says the move needs no work.
public enum WorkspaceSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [WorkspaceSchemaV1.Workspace.self, StoredState.self]
    }

    /// One blob of the app's own state, keyed by a string.
    ///
    /// Deliberately shapeless. Everything the app persists about itself — which
    /// workspaces are open, which tabs, which folders are expanded — is encoded
    /// to JSON and lands here, so adding something to persist needs no schema
    /// version and no migration. `Codable` on the snapshot does the work that
    /// a column per field would otherwise do.
    ///
    /// That is also what makes the move to plain JSON files cheap: the bytes in
    /// `data` are already exactly what a file would hold.
    @Model
    public final class StoredState {
        /// What the value is. Unique, so a save replaces rather than appends.
        @Attribute(.unique) public var key: String

        /// The encoded snapshot.
        public var data: Data

        /// When it was last written. For diagnostics, and for a future prune of
        /// state belonging to workspaces that no longer exist.
        public var updatedAt: Date

        public init(key: String, data: Data, updatedAt: Date = .now) {
            self.key = key
            self.data = data
            self.updatedAt = updatedAt
        }
    }
}

/// The current version, so callers never name a version they don't care about.
public typealias StoredState = WorkspaceSchemaV2.StoredState
