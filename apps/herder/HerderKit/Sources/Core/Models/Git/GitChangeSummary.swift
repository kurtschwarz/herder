import Foundation

/// How many lines a worktree has inserted and deleted, as `git diff
/// --shortstat` counts them.
public struct GitChangeSummary: Equatable, Sendable {
    public var insertions: Int
    public var deletions: Int

    public init(insertions: Int, deletions: Int) {
        self.insertions = insertions
        self.deletions = deletions
    }
}
