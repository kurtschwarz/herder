import Foundation

/// What the app needs to know about git before it will adopt a folder.
public protocol GitClient: Sendable {
    func repositoryKind(at url: URL) async throws -> GitRepositoryKind

    /// Every working tree of the repository at `url`, in the order the sidebar
    /// shows them. Empty for a folder that is not a repository root.
    func worktrees(at url: URL) async throws -> [GitWorktree]

    /// Local branch names of the repository at `url`, sorted. Empty for a folder
    /// that is not the root of a main working tree or a bare repository.
    func branches(at url: URL) async throws -> [String]

    /// Adds a working tree at `path` on a new branch cut from `base`.
    ///
    /// Changes the repository, unlike everything else here, so it runs `git`
    /// itself rather than reproducing what `git worktree add` writes.
    func addWorktree(in repository: URL, at path: URL, newBranch: String, from base: String) async throws

    /// Where the working tree at `url` keeps its `index` and its `HEAD`.
    ///
    /// Worth asking for separately because `git add` writes no file in the
    /// working tree at all — it writes the index — so nothing a watcher sees
    /// under the tree would ever report a change to what is staged. And for a
    /// linked worktree the answer is not inside the tree either: it is
    /// `<main repository>/.git/worktrees/<name>`, which no recursive watch on
    /// the worktree could reach.
    ///
    /// `nil` for a folder that is not a working tree.
    func gitDirectory(of url: URL) async throws -> URL?

    /// What the working tree at `url` has checked out: its branch, or the
    /// commit when `HEAD` is detached. `nil` for a folder that is not a working
    /// tree, or one whose `HEAD` cannot be read.
    func checkout(of url: URL) async throws -> GitWorktree.Checkout?

    /// What git says about every path in the working tree at `worktree`.
    ///
    /// One call for the whole tree rather than a question per folder: the cost
    /// is a single subprocess however many folders are open, which is what lets
    /// a file watcher drive this without spawning git per event. Asks git
    /// rather than reading `.gitignore` files, so nested ignore files, negated
    /// patterns and the repository's own exclude file all count. No entries for
    /// a folder outside any repository.
    func status(in worktree: URL) async throws -> GitWorktreeStatus

    /// Lines inserted and deleted in the working tree at `worktree` since it
    /// forked from the repository's default branch (see ``GitDefaultBranch``):
    /// committed and uncommitted changes to tracked files alike, which is `git
    /// diff --shortstat` against the merge-base. Untracked files are not
    /// counted. `nil` for a folder that is not a working tree, or when there is
    /// no default branch to compare with.
    func changeSummary(in worktree: URL) async throws -> GitChangeSummary?
}
