import Foundation

/// Links the opencode theme and plugin in Herder's bundle into opencode's
/// config folder. See ``OpencodeIntegration``.
public protocol OpencodeIntegrationClient: Sendable {
    /// Links each item that ``OpencodeIntegration/shouldLink(over:)`` allows.
    /// Failing changes nothing: opencode falls back to its own theme, and its
    /// sessions read as idle.
    func install() async
}
