import Foundation

/// One repository's session history, as it goes to ``StateStore``.
///
/// A file per repository, keyed by the canonical path of its main working
/// tree rather than by ``Repository/id``: removing a repository from Herder
/// and adding the same folder again mints a new id, and its history should be
/// there when it comes back.
public struct SessionHistorySnapshot: Codable, Sendable, Equatable {
    public var version = 1

    public var records: [AgentSession]

    public init(records: [AgentSession] = []) {
        self.records = records
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        records = try container.decodeIfPresent([AgentSession].self, forKey: .records) ?? []
    }

    /// What is on disk, so it is never renamed without a migration.
    /// `FileStateStore` files these under `history/`.
    public static let keyPrefix = "history:"

    public static func persistenceKey(for repository: PathKey) -> String {
        keyPrefix + repository.path
    }
}
