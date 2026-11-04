import Foundation

/// What a folder is, as far as git is concerned.
///
/// Only the distinctions the add-a-workspace flow acts on: a workspace may be a
/// main working tree or a bare repository, a linked worktree offers its main
/// repository instead, and anything else is refused.
public enum GitRepositoryKind: Sendable, Equatable {
    /// The root of an ordinary repository with a working tree.
    case mainWorkingTree

    /// A bare repository directory, the usual parent of sibling worktrees.
    case bare

    /// A worktree added with `git worktree add`, and the repository it belongs to.
    case linkedWorktree(mainRepository: URL)

    /// Not a repository root. A subdirectory of a repository counts as this: a
    /// workspace maps to a repository, not to a folder inside one.
    case notARepository
}

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

    public var id: URL { path }

    public init(path: URL, checkout: Checkout, isMainWorkingTree: Bool) {
        self.path = path
        self.checkout = checkout
        self.isMainWorkingTree = isMainWorkingTree
    }
}

/// What the app needs to know about git before it will adopt a folder.
public protocol GitClient: Sendable {
    func repositoryKind(at url: URL) async throws -> GitRepositoryKind

    /// Every working tree of the repository at `url`, in the order the sidebar
    /// shows them. Empty for a folder that is not a repository root.
    func worktrees(at url: URL) async throws -> [GitWorktree]
}
