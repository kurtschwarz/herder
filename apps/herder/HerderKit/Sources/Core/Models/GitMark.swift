/// The single marker a path carries: what git says about it, or what changed
/// inside it when it is a collapsed folder.
///
/// Staged and unstaged are collapsed into one `modified`. ``GitStatus`` keeps
/// them apart — a two-column status is what git reports and discarding it could
/// not be undone — but nothing that draws a marker has a visual language that
/// could tell "saved" from "staged" without being noise.
///
/// `Comparable` in declaration order, so the marker a folder shows is the
/// `max` of everything below it. No counts: they are noise at a glance and they
/// make the rollup expensive to keep correct.
public enum GitMark: Sendable, Equatable, Comparable {
    case untracked
    case modified
    case unmerged

    /// `nil` for ignored, which raises no marker anywhere.
    public init?(_ status: GitStatus) {
        switch status {
        case .unmerged: self = .unmerged
        case .tracked: self = .modified
        case .untracked: self = .untracked
        case .ignored: return nil
        }
    }
}
