import Core
import Foundation
import TestSupport
import Testing

@testable import TaskManagerFeature

/// The Task Manager's state, against a fake monitor and a registry the test
/// fills in: no real process is read.
@Suite(.timeLimit(.minutes(1))) struct TaskManagerModelTests {
    let monitor = StubProcessMonitorClient()
    let registry = RunningProcesses()
    let clock = VirtualClockClient()
    let workspace = WorkspaceID(PathKey(canonical: "/code/api"))
    static let app: Int32 = 100
    static let start = Date(timeIntervalSince1970: 1_000_000)

    func model(clock: (any ClockClient)? = nil) -> TaskManagerModel {
        TaskManagerModel(monitor: monitor, processes: registry, clock: clock ?? self.clock)
    }

    func process(_ pid: Int32, parent: Int32 = app, _ name: String, cpu: Double = 0, started: UInt64? = nil) -> SampledProcess {
        SampledProcess(
            pid: pid, parent: parent, name: name, cpuTime: UInt64(cpu * 1_000_000_000), footprint: 10 << 20,
            threads: 2, started: started ?? UInt64(pid)
        )
    }

    func sample(at seconds: TimeInterval, _ processes: SampledProcess...) -> ProcessSample {
        ProcessSample(
            root: Self.app, takenAt: Self.start.addingTimeInterval(seconds), coreCount: 8, physicalMemory: 16 << 30,
            processes: [process(Self.app, parent: 1, "Herder")] + processes
        )
    }

    @discardableResult
    func addAgent(
        _ title: String = "Fix", pid: Int32? = 200, state: AgentSession.State = .idle, show: @escaping @MainActor () -> Void = {}
    ) -> UUID {
        let id = UUID()
        let entry = RunningProcesses.Entry(
            id: id, kind: .agentSession, window: UUID(), workspace: workspace, pid: pid,
            title: { title }, state: { state }, show: show
        )
        registry.register(entry)
        return id
    }

    func find(_ id: TaskRow.ID, in rows: [TaskRow]) -> TaskRow? {
        for row in rows {
            if row.id == id { return row }
            if let found = find(id, in: row.children) { return found }
        }
        return nil
    }

    // MARK: Refreshing

    @Test func readsNothingUntilItRuns() {
        _ = model()

        #expect(monitor.calls == 0)
    }

    @Test func aProcessHasNoRateOnItsFirstSampleAndOneOnTheSecond() async throws {
        let model = model()
        let id = addAgent(pid: 200)
        monitor.enqueue(
            sample(at: 0, process(200, "opencode", cpu: 1)),
            sample(at: 2, process(200, "opencode", cpu: 2))
        )

        await model.refresh()
        #expect(try #require(find(.tab(id), in: model.rows)).cpu == nil)
        #expect(model.summary?.cpu == nil)

        await model.refresh()
        // One second of CPU in two.
        #expect(try #require(find(.tab(id), in: model.rows)).cpu == 50)
        #expect(model.summary?.cpu == 50)
    }

    @Test func historyGrowsWithEachRefreshAndStartsOverWhenRun() async {
        let model = model()
        monitor.enqueue(sample(at: 0), sample(at: 2), sample(at: 4))

        await model.refresh()
        await model.refresh()
        await model.refresh()

        #expect(model.memoryHistory.points.count == 3)
        // The first sample has no rate, so the CPU line starts a refresh later.
        #expect(model.cpuHistory.points.count == 2)
    }

    @Test func runRefreshesAndGoesOnUntilItsSleepEnds() async {
        let model = model(clock: EndingClock())

        await model.run()

        #expect(monitor.calls == 1)
    }

    @Test func runStopsWhenCancelled() async throws {
        let model = model(clock: ParkedClock())
        let task = Task { await model.run() }
        while monitor.calls == 0 { try await Task.sleep(for: .milliseconds(1)) }

        task.cancel()
        await task.value

        #expect(monitor.calls == 1)
    }

    @Test func runStartsFromNothing() async {
        let model = model(clock: EndingClock())
        monitor.enqueue(sample(at: 0, process(200, "x", cpu: 1)), sample(at: 2, process(200, "x", cpu: 2)))
        await model.refresh()
        await model.refresh()
        #expect(model.memoryHistory.points.count == 2)
        #expect(model.summary?.cpu != nil)

        monitor.enqueue(sample(at: 4, process(200, "x", cpu: 3)))
        await model.run()

        // The history is of this run, and nothing is a rate until it is seen twice.
        #expect(model.memoryHistory.points.count == 1)
        #expect(model.summary?.cpu == nil)
    }

    // MARK: Rows

    @Test func agentRowsComeFromTheRegistry() async throws {
        let model = model()
        let id = addAgent("Syntax highlighting", pid: 200, state: .working)
        monitor.enqueue(sample(at: 0, process(200, "opencode"), process(300, parent: 200, "make")))

        await model.refresh()

        let row = try #require(find(.tab(id), in: model.rows))
        #expect(row.name == "Syntax highlighting")
        #expect(row.status == .working)
        #expect(row.processCount == 2)
        #expect(model.summary?.sessions == 1)
    }

    @Test func sessionsAcrossWindowsAreAllCounted() async {
        let model = model()
        addAgent("a", pid: 200, state: .working)
        addAgent("b", pid: 300, state: .idle)
        monitor.enqueue(sample(at: 0, process(200, "x"), process(300, "y")))

        await model.refresh()

        #expect(model.summary?.sessions == 2)
        #expect(model.summary?.working == 1)
        #expect(model.summary?.idle == 1)
    }

    @Test func aDoneAgentIsListedUntilItsTabCloses() async throws {
        let model = model()
        let id = addAgent(pid: 200, state: .exited(1))
        monitor.enqueue(sample(at: 0, process(200, "gone")))
        await model.refresh()
        #expect(try #require(find(.tab(id), in: model.rows)).status == .done)

        registry.unregister(id)
        monitor.enqueue(sample(at: 2))
        await model.refresh()

        #expect(find(.tab(id), in: model.rows) == nil)
    }

    // MARK: Sorting and expansion

    @Test func rowsStartSortedByCPUHighestFirst() async {
        let model = model()
        let busy = addAgent("busy", pid: 200)
        let calm = addAgent("calm", pid: 300)
        monitor.enqueue(
            sample(at: 0, process(200, "a", cpu: 0), process(300, "b", cpu: 0)),
            sample(at: 2, process(200, "a", cpu: 0.2), process(300, "b", cpu: 2))
        )
        await model.refresh()
        await model.refresh()

        let sessions = model.lines.filter { $0.row.kind == .session }.map(\.id)

        #expect(sessions == [.tab(calm), .tab(busy)])
    }

    @Test func clickingAColumnSortsByIt() {
        let model = model()

        model.sort(by: .memory)
        #expect(model.order == TaskSort.Order(.memory, ascending: false))

        model.sort(by: .memory)
        #expect(model.order == TaskSort.Order(.memory, ascending: true))

        model.sort(by: .name)
        #expect(model.order == TaskSort.Order(.name, ascending: true))
    }

    @Test func aTabStartsClosedAndOpensToItsTree() async throws {
        let model = model()
        let id = addAgent(pid: 200)
        monitor.enqueue(sample(at: 0, process(200, "opencode"), process(300, parent: 200, "make")))
        await model.refresh()

        #expect(!model.lines.contains { $0.id == .process(process(200, "opencode").key) })

        model.toggleExpanded(.tab(id))
        #expect(model.lines.contains { $0.id == .process(process(200, "opencode").key) })
        #expect(try #require(model.lines.first { $0.id == .tab(id) }).isExpanded)
    }

    @Test func expansionAndSelectionSurviveARefresh() async {
        let model = model()
        let id = addAgent(pid: 200)
        monitor.enqueue(sample(at: 0, process(200, "x")), sample(at: 2, process(200, "x")))
        await model.refresh()
        model.toggleExpanded(.tab(id))
        model.selection = .process(process(200, "x").key)

        await model.refresh()

        #expect(model.expanded.contains(.tab(id)))
        #expect(model.selection == .process(process(200, "x").key))
    }

    @Test func aProcessThatGoesAwayTakesItsSelectionWithIt() async {
        let model = model()
        monitor.enqueue(sample(at: 0, process(500, "git")), sample(at: 2))
        await model.refresh()
        model.selection = .process(process(500, "git").key)

        await model.refresh()

        #expect(model.selection == nil)
    }

    // MARK: Filtering

    @Test func theFilterNarrowsAndOpensEverythingItFound() async {
        let model = model()
        addAgent("Syntax", pid: 200)
        addAgent("Other", pid: 300)
        monitor.enqueue(sample(at: 0, process(200, "opencode"), process(201, parent: 200, "cargo"), process(300, "claude")))
        await model.refresh()

        model.filter = "cargo"

        let names = model.lines.map(\.row.name)
        #expect(names.contains("cargo"))
        #expect(names.contains("Syntax"))
        #expect(!names.contains("Other"))
    }

    @Test func theScopeNarrowsToOneHalf() async {
        let model = model()
        addAgent(pid: 200)
        monitor.enqueue(sample(at: 0, process(200, "x")))
        await model.refresh()

        model.scope = .agents
        #expect(model.lines.filter { $0.depth == 0 }.map(\.id) == [.agentSessions])

        model.scope = .herder
        #expect(model.lines.filter { $0.depth == 0 }.map(\.id) == [.herder])
    }

    // MARK: The bar

    @Test func theBarSaysWhatIsSelected() async {
        let model = model()
        let id = addAgent("Syntax highlighting", pid: 200)
        monitor.enqueue(sample(
            at: 0,
            SampledProcess(pid: 200, parent: Self.app, name: "o", footprint: 1, threads: 1, started: 1),
            SampledProcess(pid: 201, parent: 200, name: "a", footprint: 1, threads: 1, started: 2)
        ))
        await model.refresh()
        #expect(model.selectionSummary == nil)

        model.selection = .tab(id)

        // Started in 1970 plus a few microseconds: long ago, in days.
        #expect(model.selectionSummary?.hasPrefix("Syntax highlighting \u{00B7} 2 processes \u{00B7} started ") == true)
    }

    @Test func showSessionIsForTabsOnly() async {
        let model = model()
        let id = addAgent(pid: 200)
        monitor.enqueue(sample(at: 0, process(200, "x")))
        await model.refresh()

        model.selection = .tab(id)
        #expect(model.canShowSession)

        model.selection = .process(process(200, "x").key)
        #expect(!model.canShowSession)

        model.selection = .agentSessions
        #expect(!model.canShowSession)
    }

    @Test func showSessionBringsTheTabForward() async {
        let model = model()
        // CONCURRENCY: counted on the main actor, by a closure that is not marked as running there.
        nonisolated(unsafe) var shown = 0
        let id = addAgent(pid: 200) { shown += 1 }
        monitor.enqueue(sample(at: 0, process(200, "x")))
        await model.refresh()
        model.selection = .tab(id)

        model.showSelectedSession()

        #expect(shown == 1)
    }

    @Test func showSessionDoesNothingForAProcess() async {
        let model = model()
        // CONCURRENCY: counted on the main actor, by a closure that is not marked as running there.
        nonisolated(unsafe) var shown = 0
        addAgent(pid: 200) { shown += 1 }
        monitor.enqueue(sample(at: 0, process(200, "x")))
        await model.refresh()
        model.selection = .process(process(200, "x").key)

        model.showSelectedSession()

        #expect(shown == 0)
    }
}

/// A clock whose first sleep fails, which is how a loop on it ends.
private struct EndingClock: ClockClient {
    var now: ContinuousClock.Instant { .now }
    func sleep(for duration: Duration) async throws { throw CancellationError() }
}

/// A clock that really waits, until the task is cancelled.
private struct ParkedClock: ClockClient {
    var now: ContinuousClock.Instant { .now }
    func sleep(for duration: Duration) async throws { try await Task.sleep(for: .seconds(60)) }
}
