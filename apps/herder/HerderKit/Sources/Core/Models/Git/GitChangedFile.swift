import Foundation

/// A tracked file whose working copy differs from a revision, with how much.
public struct GitChangedFile: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case modified
        case added
        case deleted
        case renamed
    }

    /// Relative to the worktree, with `/` separators.
    public var path: String
    /// Where a renamed file was, relative to the worktree.
    public var previousPath: String?
    public var status: Status
    public var insertions: Int
    public var deletions: Int

    public init(path: String, previousPath: String? = nil, status: Status, insertions: Int = 0, deletions: Int = 0) {
        self.path = path
        self.previousPath = previousPath
        self.status = status
        self.insertions = insertions
        self.deletions = deletions
    }
}
