import Foundation

/// Whether the settings that used to be in the `agents` and `naming`
/// snapshots have been moved into `settings.json`, as it goes to
/// ``StateStore``.
///
/// Without it, deleting the file and relaunching would import the old values
/// again, when a missing file is meant to be every setting at its default.
public struct SettingsMigrationSnapshot: Codable, Sendable, Equatable {
    /// A file name on the user's disk, so never renamed without a migration.
    public static let persistenceKey = "settings-migration"

    public var version = 1
    public var migrated: Bool

    public init(migrated: Bool = true) {
        self.migrated = migrated
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        migrated = try container.decodeIfPresent(Bool.self, forKey: .migrated) ?? false
    }
}
