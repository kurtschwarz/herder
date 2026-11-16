import Foundation

/// Why a folder was refused.
///
/// Each case carries what the UI needs to say something useful: the linked
/// worktree case names the repository to offer instead of the folder the user
/// picked.
public enum RepositoryStoreError: Error, Equatable {
    /// The folder is not a repository root. A folder inside a repository lands
    /// here too: a workspace maps to a repository, not to any folder in one.
    case notAGitRepository(URL)

    /// The folder is a `git worktree add` worktree. Worktrees appear under their
    /// repository, so the repository is what gets added.
    case isLinkedWorktree(mainRepository: URL)

    /// The folder is already a workspace.
    case alreadyOpen(URL)
}
