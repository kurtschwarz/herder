import Foundation

/// Where the naming call goes and how it identifies itself: an
/// Anthropic-compatible base URL, and the key for it where it wants one.
public struct NamingConfiguration: Sendable, Equatable {
    /// Meridian's local Anthropic-compatible API, which needs no key.
    public static let defaultEndpoint = "http://127.0.0.1:3456"

    public var endpoint: URL
    public var apiKey: String?

    public init(endpoint: URL, apiKey: String? = nil) {
        self.endpoint = endpoint
        self.apiKey = apiKey
    }
}
