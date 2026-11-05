import Core
import Foundation
import SwiftData

/// Everything the app needs to persist itself, with the SwiftData behind it
/// kept inside this module.
///
/// The composition root used to build a `ModelContainer` and hold it, which put
/// `import SwiftData` in the App target and gave the boundary rule — SwiftData
/// lives only under `Services/Persistence/` — nothing to stand on. Handing back
/// a `StateStore` and a list of `Repository` values instead means the container
/// never crosses out of here, and the move to JSON files in Phase 7 replaces
/// this type without the App target noticing.
public struct PersistenceStack {
    /// Where the app's own state goes.
    public let state: any StateStore

    private let container: ModelContainer

    private init(container: ModelContainer) {
        self.container = container
        self.state = SwiftDataStateStore(container: container)
    }

    /// Backed by the file under Application Support. Used by the app.
    public static func live() throws -> PersistenceStack {
        PersistenceStack(container: try WorkspaceContainer.live())
    }

    /// Backed by nothing, discarded with the test. Used by tests and previews.
    public static func inMemory() throws -> PersistenceStack {
        PersistenceStack(container: try WorkspaceContainer.inMemory())
    }

    /// Where the store lives, for a message that has to name it.
    public static func storeURL() throws -> URL {
        try WorkspaceContainer.storeURL()
    }

    /// The adopted repositories still in the SwiftData table Herder used to
    /// keep its list in. Empty for a store that never had any.
    ///
    /// See ``LegacyRepositoryImport``: the rows carry security-scoped
    /// bookmarks, so they are copied across rather than abandoned.
    @MainActor
    public func legacyRepositories() -> [Repository] {
        LegacyRepositoryImport(container: container).rows()
    }
}
