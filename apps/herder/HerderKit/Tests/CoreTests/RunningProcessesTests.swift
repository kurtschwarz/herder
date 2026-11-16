import Foundation
import Testing

@testable import Core

/// The registry the panels write and the Task Manager reads.
@Suite(.timeLimit(.minutes(1))) @MainActor struct RunningProcessesTests {
    let workspace = WorkspaceID(PathKey(canonical: "/code/api"))

    func entry(
        _ id: UUID = UUID(),
        kind: ProcessOwner.Kind = .agentSession,
        pid: Int32? = 200,
        title: @escaping @MainActor () -> String = { "Title" },
        show: @escaping @MainActor () -> Void = {}
    ) -> RunningProcesses.Entry {
        RunningProcesses.Entry(id: id, kind: kind, window: UUID(), workspace: workspace, pid: pid, title: title, show: show)
    }

    @Test func startsEmpty() {
        #expect(RunningProcesses().entries.isEmpty)
    }

    @Test func registersInOrder() {
        let registry = RunningProcesses()
        let first = entry()
        let second = entry()

        registry.register(first)
        registry.register(second)

        #expect(registry.entries.map(\.id) == [first.id, second.id])
    }

    @Test func registeringAgainReplacesInPlace() {
        let registry = RunningProcesses()
        let id = UUID()
        registry.register(entry(id, pid: 200))
        registry.register(entry())

        registry.register(entry(id, pid: 300))

        #expect(registry.entries.count == 2)
        #expect(registry.entries.first?.pid == 300)
    }

    @Test func aProcessThatEndedKeepsItsEntryWithoutAPid() {
        let registry = RunningProcesses()
        let id = UUID()
        registry.register(entry(id))

        registry.processEnded(id)

        #expect(registry.entry(id)?.pid == nil)
    }

    @Test func unregisteringTakesTheEntryAway() {
        let registry = RunningProcesses()
        let id = UUID()
        registry.register(entry(id))

        registry.unregister(id)

        #expect(registry.entry(id) == nil)
    }

    @Test func ownersAreReadWhenAsked() {
        let registry = RunningProcesses()
        var title = "First"
        registry.register(entry(title: { title }))

        title = "Renamed"

        #expect(registry.owners.first?.title == "Renamed")
    }

    @Test func showingCallsTheEntrysClosure() {
        let registry = RunningProcesses()
        let id = UUID()
        var shown = 0
        registry.register(entry(id, show: { shown += 1 }))

        registry.entry(id)?.show()

        #expect(shown == 1)
    }
}
