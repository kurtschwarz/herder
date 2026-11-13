import Foundation

/// What a new agent session is for. Plan starts the agent with its plan
/// command, where it has one; build is the agent's normal command.
///
/// Remembered with a session's tab, so a tab that has to start fresh after a
/// relaunch starts the way it did the first time.
public enum SessionMode: String, Codable, Sendable, Equatable, Hashable {
    case plan
    case build
}
