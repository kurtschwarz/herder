import Foundation

@testable import Core

/// Samples built by hand, so what the process logic does with them is checked
/// without any real process.
enum ProcessFixtures {
    static let start = Date(timeIntervalSince1970: 1_000_000)
    static let appPID: Int32 = 100

    /// A process started at second `started` of the fixture's clock. CPU time
    /// is in seconds, for readability.
    static func process(
        _ pid: Int32,
        parent: Int32 = appPID,
        _ name: String = "proc",
        cpu seconds: Double = 0,
        mb: UInt64 = 10,
        threads: Int = 2,
        started: UInt64? = nil,
        running: Bool = false
    ) -> SampledProcess {
        SampledProcess(
            pid: pid,
            parent: parent,
            name: name,
            commandLine: "\(name) --flag",
            cpuTime: UInt64(seconds * 1_000_000_000),
            footprint: mb << 20,
            threads: threads,
            started: started ?? UInt64(pid) * 1000,
            isRunning: running
        )
    }

    static func sample(
        at seconds: TimeInterval = 0,
        cores: Int = 8,
        pressure: MemoryPressure = .low,
        _ processes: SampledProcess...
    ) -> ProcessSample {
        ProcessSample(
            root: appPID,
            takenAt: start.addingTimeInterval(seconds),
            coreCount: cores,
            physicalMemory: 16 << 30,
            memoryPressure: pressure,
            processes: [process(appPID, parent: 1, "Herder")] + processes
        )
    }

    static func owner(
        _ kind: ProcessOwner.Kind,
        _ title: String,
        pid: Int32?,
        worktree: String = "/code/api",
        branch: String? = "main",
        state: AgentSession.State? = nil,
        window: UUID = UUID()
    ) -> ProcessOwner {
        ProcessOwner(
            id: UUID(),
            kind: kind,
            window: window,
            worktree: WorkspaceID(PathKey(canonical: worktree)),
            branch: branch,
            title: title,
            pid: pid,
            state: state ?? (kind == .agentSession ? .idle : nil)
        )
    }

    /// The rows under the group with `id`.
    static func children(of id: TaskRow.ID, in rows: [TaskRow]) -> [TaskRow] {
        func find(_ rows: [TaskRow]) -> TaskRow? {
            for row in rows {
                if row.id == id { return row }
                if let found = find(row.children) { return found }
            }
            return nil
        }
        return find(rows)?.children ?? []
    }
}
