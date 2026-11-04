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

/// What the app needs to know about git before it will adopt a folder.
public protocol GitClient: Sendable {
    func repositoryKind(at url: URL) async throws -> GitRepositoryKind
}
