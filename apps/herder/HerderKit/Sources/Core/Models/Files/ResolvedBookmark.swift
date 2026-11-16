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
