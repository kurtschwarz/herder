/// Which process a row is about, across samples.
///
/// The pid alone is not an identity: the kernel reuses them, and a process that
/// ended between two samples could be mistaken for a new one that took its
/// number, and its CPU time subtracted from the other's. A pid and the moment
/// that process started are never the same for two processes.
public struct ProcessKey: Hashable, Sendable {
    public let pid: Int32

    /// Microseconds since 1970.
    public let started: UInt64

    public init(pid: Int32, started: UInt64) {
        self.pid = pid
        self.started = started
    }
}
