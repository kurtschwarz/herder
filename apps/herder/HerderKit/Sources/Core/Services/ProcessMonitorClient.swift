/// Reads what Herder's own process tree is using.
///
/// I/O and nothing else: what a sample means (a rate, which tab a process
/// belongs to) is `ProcessCPU`'s and the Task Manager's, and runs without it.
public protocol ProcessMonitorClient: Sendable {
    /// Herder's process and every descendant, as they are now. Processes that
    /// end while it is read are left out.
    func sample() async -> ProcessSample
}
