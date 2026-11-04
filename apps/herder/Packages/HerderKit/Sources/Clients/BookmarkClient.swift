import Foundation

/// A folder the app got back from a bookmark.
public struct ResolvedBookmark: Sendable, Equatable {
    /// Where the folder is now, which need not be where it was when the bookmark
    /// was made.
    public var url: URL

    /// The bookmark still resolves but has drifted far enough that it should be
    /// remade and saved.
    public var isStale: Bool

    public init(url: URL, isStale: Bool) {
        self.url = url
        self.isStale = isStale
    }
}

public enum BookmarkClientError: Error, Equatable {
    case unresolvable
}

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
