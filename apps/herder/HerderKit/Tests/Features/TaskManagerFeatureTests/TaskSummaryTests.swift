import Foundation
import Testing

import Core

@testable import TaskManagerFeature

/// The tiles' numbers, and the history behind their sparklines.
@Suite struct TaskSummaryTests {
    typealias F = ProcessFixtures

    @Test func addsUpTheWholeTree() {
        let sample = F.sample(F.process(200, mb: 100, threads: 4), F.process(300, parent: 200, mb: 50, threads: 3))

        let summary = TaskSummary.make(sample: sample, cpu: [:], owners: [])

        // The app itself is a process with 10 MB and 2 threads, too.
        #expect(summary.processCount == 3)
        #expect(summary.memory == 160 << 20)
        #expect(summary.threads == 9)
        #expect(summary.physicalMemory == 16 << 30)
    }

    @Test func hasNoCPUUntilThereIsARate() {
        let summary = TaskSummary.make(sample: F.sample(F.process(200)), cpu: [:], owners: [])

        #expect(summary.cpu == nil)
        #expect(summary.cpuShare == nil)
    }

    @Test func cpuIsAShareOfTheWholeMachine() throws {
        let sample = F.sample(cores: 8, F.process(200))
        let cpu = [F.process(200).key: 300.0, F.process(F.appPID, parent: 1).key: 100.0]

        let summary = TaskSummary.make(sample: sample, cpu: cpu, owners: [])

        // Four cores' worth on eight cores.
        #expect(try #require(summary.cpuShare) == 0.5)
        #expect(try #require(summary.coresBusy) == 4)
        #expect(summary.coreCount == 8)
    }

    @Test func carriesTheMemoryPressure() {
        let summary = TaskSummary.make(sample: F.sample(pressure: .critical), cpu: [:], owners: [])

        #expect(summary.memoryPressure == .critical)
    }

    @Test func countsSessionsAcrossWindowsAndSplitsThem() {
        let owners = [
            F.owner(.agentSession, "a", pid: 1, worktree: "/code/api", state: .working),
            F.owner(.agentSession, "b", pid: 2, worktree: "/code/api", state: .needsInput(nil)),
            F.owner(.agentSession, "c", pid: 3, worktree: "/code/web", state: .idle),
            F.owner(.agentSession, "d", pid: nil, worktree: "/code/web", state: .exited(0)),
            F.owner(.terminal, "zsh", pid: 4, worktree: "/code/mobile"),
        ]

        let summary = TaskSummary.make(sample: F.sample(), cpu: [:], owners: owners)

        #expect(summary.sessions == 4)
        #expect(summary.working == 1)
        #expect(summary.waiting == 1)
        #expect(summary.idle == 2)
        // A terminal's worktree is not a workspace with a session in it.
        #expect(summary.workspaces == 2)
    }

    @Test func historyKeepsOnlyTheLastMinute() {
        var history = MetricHistory()
        let start = Date(timeIntervalSince1970: 1000)

        for step in 0..<40 { history.append(Double(step), at: start.addingTimeInterval(Double(step) * 2)) }

        // 2 s apart over 78 s: the newest point and the thirty before it.
        #expect(history.points.count == 31)
        #expect(history.points.last?.value == 39)
        #expect(history.points.first?.value == 9)
    }

    @Test func historyStartsEmpty() {
        #expect(MetricHistory().points.isEmpty)
    }
}
