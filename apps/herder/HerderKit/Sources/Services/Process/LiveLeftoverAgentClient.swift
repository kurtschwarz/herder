import Core
import Darwin
import Foundation

/// Finds leftover agents among the user's own processes and ends them:
/// SIGTERM, then SIGKILL for any still there after ``grace``.
///
/// SIGTERM and not the hang-up a closed tab gets first, because a leftover
/// has already had its terminal go and ignored it.
public struct LiveLeftoverAgentClient: LeftoverAgentClient {
    static let grace: Duration = .seconds(2)

    public init() {}

    @concurrent
    public func endLeftovers() async {
        let leftovers = Self.processes().filter { process in
            guard let environment = ProcessArguments.environment(of: process.pid) else { return false }
            return AgentMark.isLeftover(pid: process.pid, parent: process.parent, environment: environment)
        }
        guard !leftovers.isEmpty else { return }
        for process in leftovers { Self.signal(process, SIGTERM) }

        try? await Task.sleep(for: Self.grace)
        for process in leftovers { Self.signal(process, SIGKILL) }
    }

    /// A process as it was when listed. `started` tells it from a later one
    /// given the same pid.
    struct Process {
        let pid: pid_t
        let parent: pid_t
        /// Microseconds since 1970.
        let started: UInt64
    }

    /// Signals `process` if it is still the one that was listed.
    private static func signal(_ process: Process, _ signal: Int32) {
        guard info(of: process.pid)?.started == process.started else { return }
        kill(process.pid, signal)
    }

    /// This user's processes. Another user's environment cannot be read
    /// anyway.
    static func processes() -> [Process] {
        let uid = getuid()
        let count = proc_listpids(UInt32(PROC_UID_ONLY), uid, nil, 0)
        guard count > 0 else { return [] }
        // Room for a few started between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(count) / MemoryLayout<pid_t>.size + 32)
        let filled = proc_listpids(
            UInt32(PROC_UID_ONLY), uid, &pids, Int32(pids.count * MemoryLayout<pid_t>.size)
        )
        guard filled > 0 else { return [] }
        return pids.prefix(Int(filled) / MemoryLayout<pid_t>.size)
            .filter { $0 > 0 }
            .compactMap(info(of:))
    }

    private static func info(of pid: pid_t) -> Process? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Process(
            pid: pid,
            parent: pid_t(info.pbi_ppid),
            started: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
        )
    }
}
