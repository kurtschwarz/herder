import Foundation

/// Standing permission to reach a folder the user chose.
///
/// The app is sandboxed, so a path alone cannot be reopened on the next launch.
/// A security-scoped bookmark can: it encodes both which folder it is and the
/// sandbox's permission to reach it. Access has to be switched on before use and
/// off afterwards, which is what `startAccessing` and `stopAccessing` are for.
public protocol BookmarkClient: Sendable {
    func makeBookmark(for url: URL) throws -> Data
    func resolve(_ bookmark: Data) throws -> ResolvedBookmark

    /// Returns whether access was granted. Must be balanced by `stopAccessing`.
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}
