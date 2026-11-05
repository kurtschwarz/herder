import Clients
import Worktrees

/// What a row shows about git's view of it.
///
/// Staged and unstaged are collapsed into one `modified`. The model keeps them
/// apart — a two-column status is what git reports and discarding it could not
/// be undone — but the tree does not yet have a visual language that could tell
/// "saved" from "staged" without being noise.
public enum ExplorerMark: Equatable, Sendable {
    case untracked
    case modified
    case unmerged

    /// `nil` for ignored, which the tree says with a fade rather than a mark.
    init?(_ status: GitStatus) {
        switch status {
        case .unmerged: self = .unmerged
        case .tracked: self = .modified
        case .untracked: self = .untracked
        case .ignored: return nil
        }
    }

    init(_ rollup: GitRollup) {
        switch rollup {
        case .unmerged: self = .unmerged
        case .modified: self = .modified
        case .untracked: self = .untracked
        }
    }

    /// Git's own shorthand, which anybody who reads `git status` already knows.
    public var letter: String {
        switch self {
        case .untracked: "?"
        case .modified: "M"
        case .unmerged: "!"
        }
    }
}
