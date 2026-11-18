import Core
import Foundation
import Observation

/// What the selection prompt is showing while it is open: the lines it refers
/// to, what has been typed, and which session it is aimed at.
///
/// Made when the prompt opens, from a selection that is then frozen, and gone
/// when it closes. What is typed outlives it: see ``SelectionPromptController``.
@Observable
final class SelectionPromptState {
    let ref: CodeRef

    /// What has been typed.
    var feedback: String

    /// The session picked from the chip, or `nil` for the one in front.
    var chosen: UUID?

    init(ref: CodeRef, feedback: String) {
        self.ref = ref
        self.feedback = feedback
    }

    /// The session the prompt is aimed at: the one picked, else the one in
    /// front in the panel, else the first there is.
    func target(among sessions: [AgentSession], focused: UUID?) -> AgentSession? {
        for id in [chosen, focused] {
            if let id, let session = sessions.first(where: { $0.id == id }) { return session }
        }
        return sessions.first
    }

    /// Whether a session can be typed at: only one whose terminal UI is
    /// running. Working and waiting ones queue what they are given.
    static func accepts(_ session: AgentSession) -> Bool {
        session.state?.isRunning == true
    }
}
