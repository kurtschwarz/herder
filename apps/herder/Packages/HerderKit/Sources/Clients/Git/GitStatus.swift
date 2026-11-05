import Foundation
import Models

/// One column of git's two-letter status code: what a path has staged, or what
/// it has in the working tree and not staged.
public enum GitChange: Sendable, Equatable {
    case unchanged
    case added
    case modified
    case deleted
    case renamed
    case copied
    case typeChanged
}

/// What git knows about one path.
///
/// Both columns of the status code are kept even though the first explorer
/// collapses them into one "modified". Parsing is the same work either way, and
/// discarding the distinction here could not be undone.
public enum GitStatus: Sendable, Equatable {
    /// In the index, with what is staged and what is not. At least one side is
    /// something other than `.unchanged`: git reports nothing about a tracked
    /// path it has no change for.
    case tracked(staged: GitChange, unstaged: GitChange)

    /// A merge left conflicts in it. Its own case rather than a flavour of
    /// modified: nothing else has to be resolved before a commit can happen.
    case unmerged

    /// Not in the index, and no ignore rule covers it.
    case untracked

    /// An ignore rule covers it.
    case ignored
}

/// What one `git status` says about a whole working tree.
public struct GitWorktreeStatus: Sendable, Equatable {
    /// The working tree the entries lie under.
    public var root: PathKey

    /// Every path git reported. An untracked or ignored *folder* appears as the
    /// folder and nothing below it, because `--untracked-files=normal`
    /// collapses them: a fresh `node_modules` is one entry rather than three
    /// hundred thousand, and everything inside takes its state from the folder.
    ///
    /// Holds more paths than the tree draws. A deleted file is still here, and
    /// so is the path a rename came from, because that is the only thing that
    /// can tell a folder something went missing inside it.
    public var entries: [PathKey: GitStatus]

    public init(root: PathKey, entries: [PathKey: GitStatus] = [:]) {
        self.root = root
        self.entries = entries
    }
}
