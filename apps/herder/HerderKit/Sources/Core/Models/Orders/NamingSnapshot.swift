import Foundation

/// The naming endpoint, as it goes to ``StateStore``. The key is not here: it
/// lives in the Keychain.
public struct NamingSnapshot: Codable, Sendable, Equatable {
    /// A file name on the user's disk, so never renamed without a migration.
    public static let persistenceKey = "naming"

    public var version = 1
    public var endpoint: String

    public init(endpoint: String = NamingConfiguration.defaultEndpoint) {
        self.endpoint = endpoint
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? NamingConfiguration.defaultEndpoint
    }
}
