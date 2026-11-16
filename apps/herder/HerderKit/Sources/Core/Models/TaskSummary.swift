import Foundation

/// What the Task Manager's tiles say: the whole of Herder's tree at once, and
/// the agent sessions open.
public struct TaskSummary: Sendable, Equatable {
    /// Percent of one core, for every process. `nil` until there is a rate.
    public var cpu: Double?
    public var coreCount: Int
    public var memory: UInt64
    public var physicalMemory: UInt64
    public var memoryPressure: MemoryPressure
    public var threads: Int
    public var processCount: Int

    /// Agent sessions with a tab open, in any window.
    public var sessions: Int
    public var working: Int
    public var waiting: Int
    /// Every session that is neither of those, so the three add up.
    public var idle: Int
    public var workspaces: Int

    /// What share of the whole machine it is, 0 to 1. A core is a core's
    /// worth, so four busy cores on an eight-core machine is a half.
    public var cpuShare: Double? {
        cpu.map { $0 / (100 * Double(max(coreCount, 1))) }
    }

    public var coresBusy: Double? { cpu.map { $0 / 100 } }

    public static func make(sample: ProcessSample, cpu: [ProcessKey: Double], owners: [ProcessOwner]) -> TaskSummary {
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
