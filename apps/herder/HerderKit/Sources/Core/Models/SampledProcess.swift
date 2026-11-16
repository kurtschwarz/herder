import Foundation

/// One process as it was at the moment it was read. Raw: CPU time is what the
/// process has used in all, so a rate needs two of these (see ``ProcessCPU``).
public struct SampledProcess: Sendable, Equatable {
    public var pid: Int32
    public var parent: Int32

    /// The program's name, as Activity Monitor would list it.
    public var name: String

    /// The program and its arguments, as it was started.
    public var commandLine: String

    /// CPU time used since it started, user and system together, in nanoseconds.
    public var cpuTime: UInt64

    /// Physical footprint in bytes, which is what Activity Monitor's Memory
    /// column shows and not the resident size.
    public var footprint: UInt64

    public var threads: Int

    /// Microseconds since 1970. With the pid, what identifies it: see
    /// ``ProcessKey``.
    public var started: UInt64

    /// Whether any of its threads is on a CPU right now.
    public var isRunning: Bool

    public init(
        pid: Int32,
        parent: Int32,
        name: String,
        commandLine: String = "",
        cpuTime: UInt64 = 0,
        footprint: UInt64 = 0,
        threads: Int = 1,
        started: UInt64 = 0,
        isRunning: Bool = false
    ) {
        self.pid = pid
        self.parent = parent
        self.name = name
        self.commandLine = commandLine.isEmpty ? name : commandLine
        self.cpuTime = cpuTime
        self.footprint = footprint
        self.threads = threads
        self.started = started
        self.isRunning = isRunning
    }

    public var key: ProcessKey { ProcessKey(pid: pid, started: started) }

    public var startedAt: Date { Date(timeIntervalSince1970: Double(started) / 1_000_000) }
}
