import Core
import Foundation

/// What the Task Manager's tiles say: the whole of Herder's tree at once, and
/// the agent sessions open.
struct TaskSummary: Sendable, Equatable {
    /// Percent of one core, for every process. `nil` until there is a rate.
    var cpu: Double?
    var coreCount: Int
    var memory: UInt64
    var physicalMemory: UInt64
    var memoryPressure: MemoryPressure
    var threads: Int
    var processCount: Int

    /// Agent sessions with a tab open, in any window.
    var sessions: Int
    var working: Int
    var waiting: Int
    /// Every session that is neither of those, so the three add up.
    var idle: Int
    var workspaces: Int

    /// What share of the whole machine it is, 0 to 1. A core is a core's
    /// worth, so four busy cores on an eight-core machine is a half.
    var cpuShare: Double? {
        cpu.map { $0 / (100 * Double(max(coreCount, 1))) }
    }

    var coresBusy: Double? { cpu.map { $0 / 100 } }

    static func make(sample: ProcessSample, cpu: [ProcessKey: Double], owners: [ProcessOwner]) -> TaskSummary {
        let rates = sample.processes.compactMap { cpu[$0.key] }
        let sessions = owners.filter { $0.kind == .agentSession }
        var working = 0
        var waiting = 0
        for session in sessions {
            switch session.state {
            case .working: working += 1
            case .needsInput: waiting += 1
            default: break
            }
        }
        return TaskSummary(
            cpu: rates.isEmpty ? nil : rates.reduce(0, +),
            coreCount: sample.coreCount,
            memory: sample.processes.reduce(0) { $0 + $1.footprint },
            physicalMemory: sample.physicalMemory,
            memoryPressure: sample.memoryPressure,
            threads: sample.processes.reduce(0) { $0 + $1.threads },
            processCount: sample.processes.count,
            sessions: sessions.count,
            working: working,
            waiting: waiting,
            idle: sessions.count - working - waiting,
            workspaces: Set(sessions.map(\.worktree)).count
        )
    }
}
