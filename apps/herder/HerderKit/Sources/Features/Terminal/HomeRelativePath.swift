import Foundation

/// A path as people write it: `~` for the home folder and what is under it.
enum HomeRelativePath {
    static func label(for url: URL, home: URL) -> String {
        let path = normalised(url)
        let home = normalised(home)
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// Without a trailing slash, which a directory URL carries and a prefix
    /// check would trip on.
    private static func normalised(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
