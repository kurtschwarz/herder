import Foundation

/// A path as people write it: `~` for the home folder and what is under it.
///
/// In Core because two features write paths this way: the terminal's header,
/// and the editor's breadcrumb for a file outside any workspace.
public enum HomeRelativePath {
    public static func label(for url: URL, home: URL) -> String {
        let path = normalised(url)
        let home = normalised(home)
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// The steps of ``label(for:home:)``, for a breadcrumb: `~` and each name
    /// below it, or `/` and each name below that for a path outside home.
    public static func components(for url: URL, home: URL) -> [String] {
        let label = label(for: url, home: home)
        let names = label.split(separator: "/").map(String.init)
        return label.hasPrefix("/") ? ["/"] + names : names
    }

    /// Without a trailing slash, which a directory URL carries and a prefix
    /// check would trip on.
    private static func normalised(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
