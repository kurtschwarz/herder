import Core
import Foundation
import Observation

/// One window's own state: which workspace it is showing.
///
/// Per window, not per app. Two windows showing different checkouts of the same
/// repository is the thing Herder is for, so "active" cannot be a single fact
/// held somewhere central — which is exactly what it used to be, a pair of
/// properties on the repository list's model backed by `UserDefaults`.
///
/// Switching is the whole of what this does. It sets an id and nothing else: no
/// workspace is torn down, no documents are closed, no agent is stopped. What
/// the window shows is resolved from the id by the root view.
@Observable
final class WindowModel {
    /// The workspace this window is showing, or `nil` for none.
    private(set) var activeWorkspaceID: WorkspaceID?

    init(activeWorkspaceID: WorkspaceID? = nil) {
        self.activeWorkspaceID = activeWorkspaceID
    }

    /// Shows `id`, or nothing. Asking for what is already showing changes
    /// nothing, so a repeat click does not restart the work the change drives.
    func activate(_ id: WorkspaceID?) {
        guard id != activeWorkspaceID else { return }
        activeWorkspaceID = id
    }
}
