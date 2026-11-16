import Core
import Foundation
@testable import Services
import Testing

/// Against real processes: this one, and children started for the purpose.
@Suite(.timeLimit(.minutes(1))) struct LiveProcessMonitorClientTests {
    /// Starts `/bin/sh` running `script` and returns it once it is up.
    func start(_ script: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", script]
        try process.run()
        return process
    }

    /// Samples until `found` says the sample has what it was waiting for: a
    /// child that has only just been started may not have exec'd yet.
    func sample(
        _ client: LiveProcessMonitorClient, until found: (ProcessSample) -> Bool
    ) async throws -> ProcessSample {
        var latest = await client.sample()
        for _ in 0..<200 where !found(latest) {
            try await Task.sleep(for: .milliseconds(25))
            latest = await client.sample()
        }
        return latest
    }

    @Test func includesTheRootItself() async throws {
        let sample = await LiveProcessMonitorClient().sample()

        let root = try #require(sample.processes.first { $0.pid == getpid() })
        #expect(sample.root == getpid())
        #expect(root.footprint > 0)
        #expect(root.threads >= 1)
        #expect(root.started > 0)
        #expect(root.cpuTime > 0)
        #expect(!root.name.isEmpty)
    }

    @Test func carriesWhatItsSampleIsMeasuredAgainst() async {
        let sample = await LiveProcessMonitorClient().sample()

        #expect(sample.coreCount == ProcessInfo.processInfo.activeProcessorCount)
        #expect(sample.physicalMemory == ProcessInfo.processInfo.physicalMemory)
        #expect(abs(sample.takenAt.timeIntervalSinceNow) < 5)
    }

    @Test func findsChildrenAndGrandchildren() async throws {
        // A shell that starts a sleep and waits on it.
        let shell = try start("sleep 30 & wait")
        defer { shell.terminate() }

        let sample = try await sample(LiveProcessMonitorClient()) { sample in
            sample.processes.contains { $0.name == "sleep" && $0.parent == shell.processIdentifier }
        }

        let child = try #require(sample.processes.first { $0.pid == shell.processIdentifier })
        #expect(child.parent == getpid())
        let grandchild = try #require(sample.processes.first { $0.parent == child.pid && $0.name == "sleep" })
        #expect(grandchild.commandLine.contains("sleep"))
        #expect(grandchild.key != child.key)
    }

    @Test func aRootOfItsOwnIsTheOnlyTreeRead() async throws {
        let shell = try start("sleep 30")
        defer { shell.terminate() }

        let sample = try await sample(LiveProcessMonitorClient(root: shell.processIdentifier)) { sample in
            sample.processes.contains { $0.name == "sleep" }
        }

        #expect(sample.root == shell.processIdentifier)
        #expect(!sample.processes.contains { $0.pid == getpid() })
    }

    @Test func aBusyProcessUsesMoreCPUTimeAsTimeGoesOn() async throws {
        let spinner = try start("while :; do :; done")
        defer { spinner.terminate() }
        let client = LiveProcessMonitorClient()

        let first = try await sample(client) { $0.processes.contains { $0.pid == spinner.processIdentifier } }
        try await Task.sleep(for: .milliseconds(300))
        let second = await client.sample()

        let before = try #require(first.processes.first { $0.pid == spinner.processIdentifier })
        let after = try #require(second.processes.first { $0.pid == spinner.processIdentifier })
        #expect(after.key == before.key)
        #expect(after.cpuTime > before.cpuTime)
        let rate = try #require(ProcessCPU.percentages(from: first, to: second)[after.key])
        #expect(rate > 10)
    }
}
