import Core
import Foundation

/// What the popover showed last time, kept on the workspace so the next
/// opening starts with it already on screen and the answers that arrive
/// afterwards change values in place instead of adding rows.
///
/// Not persisted: it is a hint about the repository, and the repository may
/// have moved on by the next launch.
final class DiffBaseCache: WorkspaceUIState {
    var upstreamName: String?
    var counts: [DiffBasePickerModel.Preset: GitChangeSummary] = [:]
    var hasPreviousCommit = true
    var refs: [GitRef] = []
    var commits: [GitCommit] = []
    var loadedAt: Date?

    init() {}
}
