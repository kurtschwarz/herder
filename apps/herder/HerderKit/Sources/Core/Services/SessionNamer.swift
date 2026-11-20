import Foundation

/// Asks a model what to call a new order, so its branch and session have
/// names before anything is created.
public protocol SessionNamer: Sendable {
    /// Throws when the endpoint cannot be reached, refuses, or says something
    /// that is not a name. The caller decides how long to wait.
    func name(for prompt: String, using configuration: NamingConfiguration) async throws -> SessionName
}
