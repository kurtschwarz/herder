import Foundation

/// ``SessionNamer`` with nobody to ask, for a test or a preview that must not
/// reach a real endpoint. Every call fails, so an order is named by its
/// fallback.
public struct UnavailableSessionNamer: SessionNamer {
    public struct Unavailable: Error, Equatable {}

    public init() {}

    public func name(for prompt: String, using configuration: NamingConfiguration) async throws -> SessionName {
        throw Unavailable()
    }
}
