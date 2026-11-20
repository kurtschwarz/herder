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
    /// Changes the repository, unlike everything else here.
    func addWorktree(in repository: URL, at path: URL, newBranch: String, from base: String) async throws

    /// Fetches the remote's default branch in the repository at `repository`,
    /// and only that, then names the ref a new branch should be cut from:
    /// `origin/main`, or the local `main` or `master` when there is no remote.
    /// `nil` when there is no default branch at all.
    ///
    /// A fetch that fails, offline or without credentials, is not an error:
    /// the remote-tracking ref as it stands is named all the same. Throws only
    /// when the answer could not be had, such as a daemon too old to fetch.
    ///
    /// Changes the repository, as `addWorktree` does.
    func fetchDefaultBranch(in repository: URL) async throws -> String?

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
    /// forked from the repository's default branch (`origin/HEAD`, else `main`, else `master`):
    /// committed and uncommitted changes to tracked files alike, which is `git
    /// diff --shortstat` against the merge-base. Untracked files are not
    /// counted. `nil` for a folder that is not a working tree, or when there is
    /// no default branch to compare with.
    func changeSummary(in worktree: URL) async throws -> GitChangeSummary?

    /// What `file` contained at `revision` in the working tree at `worktree`.
    /// `nil` when the file is not in that revision, or is not UTF-8.
    func contents(of file: URL, atRevision revision: String, in worktree: URL) async throws -> String?

    /// The merge-base of `HEAD` and `ref`, as a SHA. `nil` when `ref` names
    /// nothing, or shares no history with `HEAD`.
    ///
    /// The merge-base rather than `ref` itself, so that commits other people
    /// pushed to a moved upstream do not show up as changes made here. For an
    /// ancestor such as `HEAD~1` the merge-base is the ref.
    func mergeBase(of ref: String, in worktree: URL) async throws -> String?

    /// What the branch checked out in `worktree` tracks, such as `origin/main`,
    /// or the repository's default branch (`origin/HEAD`, else `main`, else `master`) when it
    /// tracks nothing. `nil` when there is neither.
    func upstream(in worktree: URL) async throws -> String?

    /// Lines inserted and deleted in tracked files between `sha` and the
    /// working tree, staged and unstaged together. `nil` when git cannot say.
    func shortstat(since sha: String, in worktree: URL) async throws -> GitChangeSummary?

    /// Tracked files whose working copy differs from `sha`, staged and
    /// unstaged together, sorted by path. Untracked and ignored files are not
    /// in it.
    func changedFiles(since sha: String, in worktree: URL) async throws -> [GitChangedFile]

    /// Local branches, remote branches and tags, newest tip first.
    func refs(in worktree: URL) async throws -> [GitRef]

    /// The `limit` most recent commits reachable from `HEAD`.
    func recentCommits(limit: Int, in worktree: URL) async throws -> [GitCommit]

    /// The commit `revision` names, for a SHA or an abbreviation of one. `nil`
    /// when it names no commit.
    func commit(matching revision: String, in worktree: URL) async throws -> GitCommit?
}
