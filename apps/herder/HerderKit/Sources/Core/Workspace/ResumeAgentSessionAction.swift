import Foundation

/// Asks for a session from the history to be picked up again: its worktree
/// shown, and the agent resumed in a tab of its own.
///
/// For the sidebar's history, which cannot reach the agent panel itself.
/// Shaped like ``ShowAgentSessionAction``, and carried the same way.
@MainActor
public struct ResumeAgentSessionAction {
    private let handler: (SessionHistoryRecord) -> Void

    public init(_ handler: @escaping (SessionHistoryRecord) -> Void) {
        self.handler = handler
    }

    public func callAsFunction(_ record: SessionHistoryRecord) {
        handler(record)
    }
}

extension ResumeAgentSessionAction {
    /// Does nothing, so a feature drawn without a window around it still
    /// builds.
    public static let inert = ResumeAgentSessionAction { _ in }
}
