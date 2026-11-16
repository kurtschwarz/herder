/// What git knows about one path.
///
/// Both columns of the status code are kept even though the file tree
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
