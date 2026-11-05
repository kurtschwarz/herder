import Core
import Foundation
import Observation

/// Which folders are open in the tree, for one workspace.
///
/// On the workspace rather than in the model, because the model is rebuilt
/// whenever the pane shows a different checkout and `@State` is discarded
/// whenever SwiftUI swaps the view out. Expansion is something the user did to
/// a particular worktree, so it belongs to that worktree and lasts as long as
/// it does.
///
/// `internal`: `Core` holds this without knowing the type, which is what keeps
/// one feature's UI state out of reach of every other.
@Observable
final class ExplorerUIState: PersistedWorkspaceUIState {
    static let persistenceKey = "explorer.expanded"

    /// Open folders below the root. The root itself is always open and is never
    /// in here.
    var expanded: Set<PathKey> = []

    init() {}

    /// Encoded as paths rather than as `PathKey`s.
    ///
    /// `PathKey` is deliberately not `Codable`: its whole point is that it can
    /// only be made by canonicalising, and a decoder handing one back from
    /// arbitrary JSON would skip that. So the keys go out as the strings they
    /// already are and come back in through `init(canonical:)`, which is sound
    /// because what was written was canonical when it was written.
    func encode() throws -> Data {
        try JSONEncoder().encode(expanded.map(\.path).sorted())
    }

    func restore(from data: Data) throws {
        expanded = Set(try JSONDecoder().decode([String].self, from: data).map(PathKey.init(canonical:)))
    }
}
