import Foundation

/// What the selection prompt types into an agent session for each of its
/// actions.
struct SelectionMessage: Equatable {
    enum Action: Equatable {
        /// The ref and the feedback, then Return.
        case send
        /// The ref and the feedback, left in the agent's prompt for more to be
        /// added to.
        case addToContext
        case explain
        case fix
        case writeTests

        /// Fixed for now: not something the person configures.
        var request: String? {
            switch self {
            case .send, .addToContext: nil
            case .explain: "Explain what this code does."
            case .fix: "Find and fix the problem in this code."
            case .writeTests: "Write tests covering this code."
            }
        }

        var submits: Bool { self != .addToContext }
    }

    /// Pasted into the session's terminal.
    var text: String

    /// Whether Return follows it.
    var submit: Bool

    /// The ref, a blank line, then what is asked: the action's sentence if it
    /// has one, and the feedback as typed.
    init(_ action: Action, ref: CodeRef, feedback: String) {
        let feedback = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = [action.request, feedback.isEmpty ? nil : feedback].compactMap { $0 }.joined(separator: "\n")
        text = "\(ref.text)\n\n\(body)"
        submit = action.submits
    }
}
