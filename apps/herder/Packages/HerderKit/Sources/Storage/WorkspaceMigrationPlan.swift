import Foundation
import SwiftData

/// How the store gets from each schema version to the next.
///
/// New versions are appended here with a stage apiece. A stage is `lightweight`
/// when SwiftData can work the change out on its own — adding a model, adding
/// an optional property — and `custom` when data has to be rewritten.
///
/// Nothing here may lose a ``Workspace``. Its name, its sidebar order and above
/// all its security-scoped bookmark cannot be rebuilt from disk: the bookmark is
/// the sandbox's standing permission to reopen a folder, and regenerating one
/// means asking the user to find the folder again in an open panel.
public enum WorkspaceMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [WorkspaceSchemaV1.self, WorkspaceSchemaV2.self]
    }

    public static var stages: [MigrationStage] {
        // V2 only adds `StoredState`. The `Workspace` table is untouched, so
        // there is nothing to rewrite and nothing to lose.
        [.lightweight(fromVersion: WorkspaceSchemaV1.self, toVersion: WorkspaceSchemaV2.self)]
    }
}
