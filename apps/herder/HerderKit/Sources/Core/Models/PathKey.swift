import Foundation

/// A file or folder path in the one spelling the app keys on: absolute, with
/// symlinks resolved and no trailing slash.
///
/// Two `URL`s can spell the same place several ways, and the places this app
/// handles arrive from sources that disagree: a security-scoped bookmark keeps
/// `/var/folders/…`, while `git` and the file watcher both hand back
/// `/private/var/folders/…`. Keyed on raw `URL`s, a watcher event would never
/// match the folder it reported — the watcher would look like it worked and
/// update nothing. Normalising here, once, is what makes a key comparable by
/// construction rather than at each comparison site.
public struct PathKey: Hashable, Sendable, Comparable, CustomStringConvertible {
    /// Absolute, resolved, with no trailing slash. The volume root keeps its.
    public let path: String

    /// Canonicalises `url`. The only way to make a key from a path that came
    /// from anywhere else.
    ///
    /// Costs a `stat` per component that is not there and a `realpath` on the
    /// rest, so prefer `appending(_:)` when building many keys below a root
    /// that is already canonical.
    ///
    /// `resolvingSymlinksInPath()` alone is not enough: handed a path whose
    /// last components do not exist it gives up and resolves nothing, not even
    /// the part that does exist. A path git reports for a file it has seen
    /// deleted is exactly that shape, and a key for it has to come out equal to
    /// the one built while the file was still there. So the deepest part that
    /// does exist is resolved and the rest appended back on.
    public init(_ url: URL) {
        var missing: [String] = []
        var current = url.standardizedFileURL

        while true {
            let path = current.path(percentEncoded: false)
            if path == "/" || FileManager.default.fileExists(atPath: path) {
                var key = PathKey(canonical: current.resolvingSymlinksInPath().path(percentEncoded: false))
                for name in missing.reversed() { key = key.appending(name) }
                self = key
                return
            }
            let name = current.lastPathComponent
            let parent = current.deletingLastPathComponent()
            // Nowhere left to walk up to: a relative path, or one so odd that
            // the best available answer is what was handed in.
            guard name.isEmpty == false, parent.path(percentEncoded: false) != path else {
                self.init(canonical: path)
                return
            }
            missing.append(name)
            current = parent
        }
    }

    /// For a path already known to be in this spelling, normalising only the
    /// trailing slash.
    ///
    /// Only for paths derived from a key that is already canonical — a child of
    /// a canonicalised folder, say. A path handed over by the system is *not*
    /// canonical, however resolved it looks: FSEvents reports
    /// `/private/var/folders/…` where this type's canonical form, and
    /// `resolvingSymlinksInPath()`, is `/var/folders/…`. Trusting one of those
    /// produces a key that matches nothing, silently.
    public init(canonical path: String) {
        var path = path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        self.path = path
    }

    /// `relative` joined below this key, resolving nothing: both sides are
    /// already in the one spelling, and a path git reports for a file it has
    /// seen deleted has nothing left on disk to resolve.
    public func appending(_ relative: String) -> PathKey {
        PathKey(canonical: path == "/" ? "/" + relative : path + "/" + relative)
    }

    /// The folder holding this one, or `nil` at the root of the volume.
    public var parent: PathKey? {
        guard path != "/", let slash = path.lastIndex(of: "/") else { return nil }
        return PathKey(canonical: slash == path.startIndex ? "/" : String(path[..<slash]))
    }

    public var name: String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }

    /// Whether this is `ancestor` or lies below it.
    public func isInside(_ ancestor: PathKey) -> Bool {
        path == ancestor.path || path.hasPrefix(ancestor.path == "/" ? "/" : ancestor.path + "/")
    }

    /// The folders between this key and `root`, nearest first and ending with
    /// `root` itself. Empty when this key is `root` or lies outside it.
    public func parents(upTo root: PathKey) -> [PathKey] {
        guard path != root.path, isInside(root) else { return [] }
        var result: [PathKey] = []
        var current = self
        while let parent = current.parent {
            result.append(parent)
            if parent.path == root.path { break }
            current = parent
        }
        return result
    }

    /// Carries no trailing slash, so a folder's `URL` does not end in one.
    public var url: URL { URL(filePath: path) }

    public var description: String { path }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.path < rhs.path }
}
