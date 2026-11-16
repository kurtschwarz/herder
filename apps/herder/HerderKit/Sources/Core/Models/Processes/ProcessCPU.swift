import Foundation

/// CPU use as a rate, from the CPU time two samples saw.
public enum ProcessCPU {
    /// For each process in `current` that `previous` also saw, the share of
    /// one core it used between them, as a percentage: 100 is one core's worth,
    /// and a process on four threads can reach 400, as in Activity Monitor.
    ///
    /// A process is the same one only if its pid and start time both match, so
    /// a pid the kernel reused starts over. One with no entry has been seen
    /// once, and has no rate yet.
    public static func percentages(from previous: ProcessSample?, to current: ProcessSample) -> [ProcessKey: Double] {
        guard let previous else { return [:] }
        let elapsed = current.takenAt.timeIntervalSince(previous.takenAt)
        guard elapsed > 0 else { return [:] }

        let before = Dictionary(previous.processes.map { ($0.key, $0.cpuTime) }, uniquingKeysWith: { first, _ in first })
        var result: [ProcessKey: Double] = [:]
        for process in current.processes {
            guard let earlier = before[process.key], process.cpuTime >= earlier else { continue }
            result[process.key] = Double(process.cpuTime - earlier) / (elapsed * 1_000_000_000) * 100
        }
        return result
    }
}
