import Foundation

/// Which checkout a ``Workspace`` is.
///
/// The canonical path of its folder, and nothing else. A workspace *is* a
/// folder — two of them for the same folder would be two views of one truth —
/// so the folder is what identifies it, and ``WorkspaceRegistry`` keys on this
/// rather than on a number it would then have to keep a map for.
///
/// Deliberately not a `UUID`. A generated identity would have to be persisted
/// beside the path and kept in step with it, and the only thing it would buy is
/// surviving a folder move. A moved checkout is a different checkout as far as
/// git is concerned, and a worktree that goes from under the watcher is already
/// handled: the workspace marks itself unavailable.
///
/// ``Repository`` is the level that does need identity independent of its path,
/// because the user names it and arranges it and its bookmark follows the
/// folder around. That is why `Repository` has a `UUID` and this does not.
///
/// `Codable` as the path string, so a snapshot of it reads as what it is.
public struct WorkspaceID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let root: PathKey

    public init(_ root: PathKey) {
        self.root = root
    }

    /// Canonicalises `url` first. Use when the path came from outside.
    public init(_ url: URL) {
        self.init(PathKey(url))
    }

    public var url: URL { root.url }

    public var description: String { root.path }

    public init(from decoder: any Decoder) throws {
        let path = try decoder.singleValueContainer().decode(String.self)
        // Already canonical when it was written. Re-canonicalising on the way
        // in would cost a `realpath` per workspace at launch, and would quietly
        // change the identity of one whose folder has since gone.
        self.init(PathKey(canonical: path))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(root.path)
    }
}
