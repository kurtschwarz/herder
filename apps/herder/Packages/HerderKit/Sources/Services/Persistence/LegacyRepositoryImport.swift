import Core
import Foundation
import SwiftData

/// Copies the adopted repositories out of the SwiftData store and into
/// ``StateStore``, once.
///
/// Herder kept its repository list as SwiftData rows until Phase 4e. The rows
/// are the one thing in the app that cannot be rebuilt — each carries a
/// security-scoped bookmark, and regenerating one means asking the user to find
/// the folder again in an open panel — so they are copied across rather than
/// abandoned, and the table is left exactly as it was.
///
/// Runs only when the new list is empty. A user who has deleted every
/// repository since migrating would otherwise have them all come back.
public struct LegacyRepositoryImport {
    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    /// The rows still in the SwiftData table, in sidebar order.
    ///
    /// `@MainActor` for the container's `mainContext`, which is the context the
    /// rows were written through.
    @MainActor
    public func rows() -> [Repository] {
        let descriptor = FetchDescriptor<LegacyRepository>(
            sortBy: [SortDescriptor(\.order), SortDescriptor(\.addedAt)]
        )
        guard let rows = try? container.mainContext.fetch(descriptor) else { return [] }
        return rows.map {
            Repository(
                id: $0.id,
                name: $0.name,
                path: $0.path,
                bookmark: $0.bookmark,
                order: $0.order,
                addedAt: $0.addedAt
            )
        }
    }
}

/// The `@Model` the rows live in, under the name it has on disk.
///
/// Still called `Workspace` as an entity, because that is what the store
/// recorded and a `@Model` class name *is* its entity name. See
/// `WorkspaceSchemaV1`.
public typealias LegacyRepository = WorkspaceSchemaV1.Workspace
