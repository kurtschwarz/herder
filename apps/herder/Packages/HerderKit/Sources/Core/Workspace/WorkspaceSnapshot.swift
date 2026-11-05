import Foundation

/// One checkout, as it goes to ``StateStore``.
///
/// A plain struct rather than the live ``Workspace`` it comes from. Never make
/// an `@Observable` class `Codable` directly: the macro's underscored backing
/// storage leaks into the encoded keys.
///
/// Holds what exists to hold. Open tabs and agent session references belong
/// here and are absent because the features are — an editor that shows one
/// read-only file at a time has no tab list to write down. They arrive with
/// their features, as new fields with defaults, which is the whole migration
/// strategy: bump nothing, decode what's missing as empty.
public struct WorkspaceSnapshot: Codable, Sendable, Equatable {
    public var version = 1

    public var id: WorkspaceID

    /// Per-feature UI state, keyed by ``PersistedWorkspaceUIState/persistenceKey``.
    ///
    /// Opaque on purpose. The workspace holds state it cannot interpret so that
    /// adding something a feature wants remembered needs no change here.
    public var uiState: [String: Data]

    public init(id: WorkspaceID, uiState: [String: Data] = [:]) {
        self.id = id
        self.uiState = uiState
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        id = try container.decode(WorkspaceID.self, forKey: .id)
        uiState = try container.decodeIfPresent([String: Data].self, forKey: .uiState) ?? [:]
    }
}
