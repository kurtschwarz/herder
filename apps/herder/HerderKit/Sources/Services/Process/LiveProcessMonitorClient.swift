import Core
import Darwin
import Foundation

/// Reads Herder's process tree with libproc: the descendants of the app's own
/// process, each with `proc_pidinfo` and `proc_pid_rusage`.
///
/// Not sandboxed, so any process of the same user can be read, which the
/// tree is. A process that ends between being listed and being read is left
/// out.
public struct LiveProcessMonitorClient: ProcessMonitorClient {
    private let root: pid_t

    public init(root: pid_t = getpid()) {
        self.root = root
    }

    @concurrent
    public func sample() async -> ProcessSample {
        let timebase = Self.timebase()
        return ProcessSample(
            root: root,
            takenAt: Date(),
            coreCount: ProcessInfo.processInfo.activeProcessorCount,
            physicalMemory: ProcessInfo.processInfo.physicalMemory,
            memoryPressure: Self.memoryPressure(),
            processes: Self.tree(from: root).compactMap { Self.read($0, timebase: timebase) }
        )
    }

    // MARK: The tree

    /// `root` and everything under it, found a level at a time. A pid is
    /// visited once however it came to be listed.
    static func tree(from root: pid_t) -> [pid_t] {
        var found: [pid_t] = [root]
        var seen: Set<pid_t> = [root]
        var index = 0
        while index < found.count {
            for child in children(of: found[index]) where seen.insert(child).inserted {
                found.append(child)
            }
            index += 1
        }
        return found
    }

    private static func children(of pid: pid_t) -> [pid_t] {
        var capacity = 64
        while true {
            var pids = [pid_t](repeating: 0, count: capacity)
            let count = Int(proc_listchildpids(pid, &pids, Int32(capacity * MemoryLayout<pid_t>.size)))
            guard count > 0 else { return [] }
            // A full buffer may have been cut short.
            if count < capacity { return pids.prefix(count).filter { $0 > 0 } }
            capacity *= 4
        }
    }

    // MARK: A process

    private static func read(_ pid: pid_t, timebase: mach_timebase_info_data_t) -> SampledProcess? {
        var bsd = proc_bsdinfo()
        let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) == bsdSize else { return nil }

        var task = proc_taskinfo()
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let hasTask = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, taskSize) == taskSize

        var usage = rusage_info_v4()
        let hasUsage = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) == 0
            }
        }

        let arguments = ProcessArguments.of(pid)
        let name = name(of: pid, arguments: arguments)
        return SampledProcess(
            pid: pid,
            parent: pid_t(bsd.pbi_ppid),
            name: name,
            commandLine: commandLine(arguments, name: name),
            cpuTime: hasUsage ? nanoseconds(usage.ri_user_time &+ usage.ri_system_time, timebase) : 0,
            footprint: hasUsage ? usage.ri_phys_footprint : 0,
            threads: hasTask ? Int(task.pti_threadnum) : 1,
            started: bsd.pbi_start_tvsec * 1_000_000 + bsd.pbi_start_tvusec,
            isRunning: hasTask ? task.pti_numrunning > 0 : bsd.pbi_status == UInt32(SRUN)
        )
    }

    /// The kernel's name for it, which for an app is its bundle's, else the
    /// last component of what it was started as.
    private static func name(of pid: pid_t, arguments: [String]?) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 {
            let name = String(cString: buffer)
            if !name.isEmpty { return name }
        }
        if let first = arguments?.first { return URL(filePath: first).lastPathComponent }
        return "pid \(pid)"
    }

    private static func commandLine(_ arguments: [String]?, name: String) -> String {
        guard let arguments, !arguments.isEmpty else { return name }
        return arguments.joined(separator: " ")
    }

    // MARK: The machine

    /// CPU time comes in the CPU's own ticks, which on Apple silicon are not
    /// nanoseconds.
    private static func timebase() -> mach_timebase_info_data_t {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info.denom == 0 ? mach_timebase_info_data_t(numer: 1, denom: 1) : info
    }

    private static func nanoseconds(_ ticks: UInt64, _ timebase: mach_timebase_info_data_t) -> UInt64 {
        let (high, low) = ticks.multipliedFullWidth(by: UInt64(timebase.numer))
        return UInt64(timebase.denom).dividingFullWidth((high, low)).quotient
    }

    /// 1 is normal, 2 is warning and 4 is critical.
    private static func memoryPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .low }
        return switch level {
        case 4...: .critical
        case 2...: .warn
        default: .low
        }
    }
}
