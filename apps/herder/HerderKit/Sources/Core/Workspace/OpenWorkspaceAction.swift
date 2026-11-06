import Foundation

/// Asks for a workspace to be made the active one in this window.
///
/// Which workspace a window shows is the window's business, and windows live in
/// the App target, which no feature may import. So a feature that wants to
/// change it — the repository list, when a worktree row is clicked — says so
/// through this instead of reaching for the window itself. The App target
/// supplies it as an environment value; features call it and learn nothing
/// about what happens next.
///
/// Reading goes the other way and needs nothing: a feature takes
/// `@Environment(Workspace.self)` and gets whichever workspace this window
/// resolved. Nothing asks "which one is active?", which is what stops two
/// windows disagreeing about the answer.
///
/// Shaped like SwiftUI's own `openWindow`, so it reads the same at a call site:
/// `openWorkspace(id)`.
@MainActor
public struct OpenWorkspaceAction {
    private let handler: (WorkspaceID?) -> Void

    /// `nil` means show nothing, which is what a window does when the active
    /// workspace's folder goes away under it.
    public init(_ handler: @escaping (WorkspaceID?) -> Void) {
        self.handler = handler
    }

    public func callAsFunction(_ id: WorkspaceID?) {
        handler(id)
    }
}

extension OpenWorkspaceAction {
    /// Does nothing. The default, so a preview or a test that renders a feature
    /// without a window around it still builds.
    public static let inert = OpenWorkspaceAction { _ in }
}
