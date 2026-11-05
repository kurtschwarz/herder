import Foundation

/// One working tree of a repository, as the sidebar lists it.
///
/// Derived from the repository's layout on every read rather than persisted: a
/// worktree is created and removed with `git` in a terminal, so the app's copy
/// would be wrong more often than not.
public struct GitWorktree: Sendable, Equatable, Identifiable {
    /// What the working tree has checked out. A worktree is always on one or the
    /// other, and only one of the two is cheap to read: a branch name sits in
    /// `HEAD`, where a detached `HEAD` holds the commit itself.
    public enum Checkout: Sendable, Equatable {
        case branch(String)
        case detached(sha: String)
    }

    /// The working tree's folder. Unique within a repository, so it identifies
    /// the row.
    public var path: URL
    public var checkout: Checkout

    /// The repository's own working tree, as opposed to one added with
    /// `git worktree add`. A bare repository has none.
    public var isMainWorkingTree: Bool

    /// When the working tree last changed what it has checked out, from the
    /// repository's reflog. `nil` when git has recorded nothing for it.
    public var lastActivity: Date?

    public var id: URL { path }

    public init(
        path: URL,
        checkout: Checkout,
        isMainWorkingTree: Bool,
        lastActivity: Date? = nil
    ) {
        self.path = path
        self.checkout = checkout
        self.isMainWorkingTree = isMainWorkingTree
        self.lastActivity = lastActivity
    }
}
