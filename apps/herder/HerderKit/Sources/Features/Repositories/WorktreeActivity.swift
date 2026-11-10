import Core

/// What the sessions open in a worktree add up to, in one line: the most
/// pressing thing about them and how many are doing it.
///
/// Working outranks waiting, which outranks idle. Sessions whose terminal has
/// exited or never started are not counted: nothing is running in them.
enum WorktreeActivity: Equatable {
    case none
    case working(Int)
    case waiting(Int)
    case idle(Int)

    init(_ sessions: [AgentSession]) {
        var working = 0
        var waiting = 0
        var idle = 0
        for session in sessions {
            switch session.state {
            case .working: working += 1
            case .needsInput: waiting += 1
            case .paused, .starting, .idle: idle += 1
            case .exited, .failed, nil: break
            }
        }

        self = if working > 0 {
            .working(working)
        } else if waiting > 0 {
            .waiting(waiting)
        } else if idle > 0 {
            .idle(idle)
        } else {
            .none
        }
    }

    var label: String {
        switch self {
        case .none: "No sessions"
        case .working(let count): "\(count) working"
        case .waiting(let count): "\(count) waiting"
        case .idle(let count): "\(count) idle"
        }
    }
}
