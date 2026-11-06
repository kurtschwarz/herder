import Foundation

/// What a folder is, as far as git is concerned.
///
/// Only the distinctions the add-a-workspace flow acts on: a workspace may be a
/// main working tree or a bare repository, a linked worktree offers its main
/// repository instead, and anything else is refused.
public enum GitRepositoryKind: Sendable, Equatable {
    /// The root of an ordinary repository with a working tree.
    case mainWorkingTree

    /// A repository with no working tree of its own, the usual parent of sibling
    /// worktrees. Either a bare repository directory, or a project folder whose
    /// `.git` is a bare repository: the layout that keeps the git internals in
    /// `.git` and every checkout beside it.
    case bare

    /// A worktree added with `git worktree add`, and the repository it belongs to.
    case linkedWorktree(mainRepository: URL)

    /// Not a repository root. A subdirectory of a repository counts as this: a
    /// workspace maps to a repository, not to a folder inside one.
    case notARepository
}
