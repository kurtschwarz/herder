import Foundation

/// Herder's own process and every process under it, read at one moment, with
/// what is needed to say what share of the machine they use.
///
/// Raw and without opinions: nothing here says which process belongs to which
/// tab, or what a rate is.
public struct ProcessSample: Sendable, Equatable {
    /// Herder's own process, which the rest descend from.
    public var root: Int32

    public var takenAt: Date

    /// Logical cores, which is what 100% of the machine is measured against.
    public var coreCount: Int

    /// Bytes of RAM.
    public var physicalMemory: UInt64

    public var memoryPressure: MemoryPressure

    /// The root and every descendant, in no particular order.
    public var processes: [SampledProcess]

    public init(
        root: Int32,
        takenAt: Date,
        coreCount: Int,
        physicalMemory: UInt64,
        memoryPressure: MemoryPressure = .low,
        processes: [SampledProcess]
    ) {
        self.root = root
        self.takenAt = takenAt
        self.coreCount = coreCount
        self.physicalMemory = physicalMemory
        self.memoryPressure = memoryPressure
        self.processes = processes
    }
}
