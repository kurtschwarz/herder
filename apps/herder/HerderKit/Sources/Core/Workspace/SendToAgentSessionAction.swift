import Foundation

/// Asks for text to be put into an open agent session's terminal, as if
/// pasted there, and optionally submitted.
///
/// For the editor's selection prompt, which cannot reach the agent panel.
/// Herder does not talk to agents, only types at them, so this is all there
/// is to sending one a code reference. Shaped like ``ShowAgentSessionAction``,
/// and carried the same way.
@MainActor
public struct SendToAgentSessionAction {
    private let handler: (UUID, String, Bool) -> Void

    public init(_ handler: @escaping (UUID, String, Bool) -> Void) {
        self.handler = handler
    }

    /// `text` is pasted, so newlines in it do not submit; with `submit`, Return
    /// is pressed after it.
    public func callAsFunction(_ sessionID: UUID, text: String, submit: Bool) {
        handler(sessionID, text, submit)
    }
}

extension SendToAgentSessionAction {
    /// Does nothing, so a feature drawn without a window around it still
    /// builds.
    public static let inert = SendToAgentSessionAction { _, _, _ in }
}
