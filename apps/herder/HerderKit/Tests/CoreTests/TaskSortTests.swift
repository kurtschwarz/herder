import Foundation
import Testing

@testable import Core

/// Sorting among siblings, with the groups held in place.
@Suite struct TaskSortTests {
    func row(_ name: String, cpu: Double? = nil, memory: UInt64 = 0, started: Date? = nil, status: TaskRow.Status = .none) -> TaskRow {
        TaskRow(
            id: .tab(UUID()), kind: .session, name: name, status: status, cpu: cpu, memory: memory,
            threads: Int(memory), processCount: Int(memory), startedAt: started
        )
    }

    func names(_ rows: [TaskRow]) -> [String] { rows.map(\.name) }

    @Test func theDefaultIsCPUHighestFirst() {
        #expect(TaskSort.Order.default == TaskSort.Order(.cpu, ascending: false))
    }

    @Test func sortsByCPUWithNoRateLast() {
        let rows = [row("low", cpu: 1), row("none"), row("high", cpu: 90)]

        #expect(names(TaskSort.apply(rows, by: .default)) == ["high", "low", "none"])
        #expect(names(TaskSort.apply(rows, by: .init(.cpu, ascending: true))) == ["none", "low", "high"])
    }

    @Test func sortsByNameInNaturalOrder() {
        let rows = [row("job 10"), row("Job 2"), row("alpha")]

        #expect(names(TaskSort.apply(rows, by: .init(.name, ascending: true))) == ["alpha", "Job 2", "job 10"])
    }

    @Test func sortsByMemoryThreadsAndProcessCount() {
        let rows = [row("a", memory: 5), row("b", memory: 50), row("c", memory: 1)]

        for column in [TaskSort.Column.memory, .threads, .processes] {
            #expect(names(TaskSort.apply(rows, by: .init(column, ascending: false))) == ["b", "a", "c"])
        }
    }

    @Test func sortsByUptimeLongestFirstWhenDescending() {
        let old = Date(timeIntervalSince1970: 100)
        let new = Date(timeIntervalSince1970: 900)
        let rows = [row("new", started: new), row("gone"), row("old", started: old)]

        #expect(names(TaskSort.apply(rows, by: .init(.uptime, ascending: false))) == ["old", "new", "gone"])
    }

    @Test func sortsByStatusWithWhatNeedsThePersonFirst() {
        let rows = [row("idle", status: .idle), row("work", status: .working), row("ask", status: .needsYou)]

        #expect(names(TaskSort.apply(rows, by: .init(.status, ascending: true))) == ["ask", "work", "idle"])
    }

    @Test func equalRowsKeepTheirOrder() {
        let rows = [row("a", cpu: 1), row("b", cpu: 1), row("c", cpu: 1)]

        #expect(names(TaskSort.apply(rows, by: .default)) == ["a", "b", "c"])
    }

    @Test func rowsAreSortedAmongTheirSiblingsAtEveryLevel() {
        var parent = row("parent", cpu: 1)
        parent.children = [row("x", cpu: 1), row("y", cpu: 9)]

        let sorted = TaskSort.apply([parent, row("big", cpu: 50)], by: .default)

        #expect(names(sorted) == ["big", "parent"])
        #expect(names(sorted[1].children) == ["y", "x"])
    }

    @Test func groupsNeverReorder() {
        let groups = [
            TaskRow.group(.agentSessions, name: "Agent Sessions", children: [row("a", cpu: 1), row("b", cpu: 9)]),
            TaskRow.group(.herder, name: "Herder", children: []),
        ]

        let sorted = TaskSort.apply(groups, by: .init(.name, ascending: false))

        #expect(names(sorted) == ["Agent Sessions", "Herder"])
        #expect(names(sorted[0].children) == ["b", "a"])
    }

    @Test func herdersOwnRowAndTheGroupsKeepTheirPlaceAmongSortedRows() {
        let app = TaskRow(id: .herder, kind: .herder, name: "Herder app", cpu: 0)
        let terminals = TaskRow.group(.terminals, name: "Terminals", children: [])
        let other = TaskRow.group(.other, name: "Other", children: [])

        let sorted = TaskSort.apply([app, terminals, other], by: .default)

        #expect(names(sorted) == ["Herder app", "Terminals", "Other"])
    }
}
