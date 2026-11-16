import Core
import Foundation
import Observation

/// What the Task Manager shows: every process Herder is running, grouped by
/// the tab that started it, refreshed while the window is open.
///
/// The system is read by a ``ProcessMonitorClient`` and the tabs by the
/// ``RunningProcesses`` registry; turning the two into rows is `TaskTree`'s,
/// and sorting and filtering them is `TaskSort`'s and `TaskFilter`'s. What is
/// left here is the state a person changes: the sort, the filter, what is
/// open and what is selected, and the last minute of each tile's history.
@Observable
public final class TaskManagerModel {
    private let monitor: any ProcessMonitorClient
    private let processes: RunningProcesses
    private let clock: any ClockClient
    private let interval: Duration

    /// Every row as of the last refresh, in the order they were built. What the
    /// table shows is ``lines``, with the sort and the filter applied.
    public private(set) var rows: [TaskRow] = []

    public private(set) var summary: TaskSummary?

    /// The last minute of the tiles that draw one: the machine's share of CPU,
    /// the tree's memory in bytes, and its threads.
    public private(set) var cpuHistory = MetricHistory()
    public private(set) var memoryHistory = MetricHistory()
    public private(set) var threadHistory = MetricHistory()

    /// When the last refresh read the system, which is "now" for uptimes.
    public private(set) var sampledAt: Date?

    public private(set) var order = TaskSort.Order.default
    public var scope: TaskFilter.Scope = .all
    public var filter = ""

    public var selection: TaskRow.ID?

    /// Open rows. The groups start open and a tab's tree starts closed.
    public private(set) var expanded: Set<TaskRow.ID> = [.agentSessions, .herder, .terminals, .other]

    @ObservationIgnored private var previous: ProcessSample?

    public init(
        monitor: any ProcessMonitorClient,
        processes: RunningProcesses,
        clock: any ClockClient,
        interval: Duration = .seconds(2)
    ) {
        self.monitor = monitor
        self.processes = processes
        self.clock = clock
        self.interval = interval
    }

    // MARK: Refreshing

    /// Refreshes once an ``interval`` until cancelled. Run from the view's
    /// `.task`, so it lasts as long as the window does and nothing reads the
    /// system while it is closed.
    ///
    /// Starts from nothing: the history is of this window being open, and a
    /// process has no rate until it has been seen twice.
    public func run() async {
        previous = nil
        cpuHistory = MetricHistory()
        memoryHistory = MetricHistory()
        threadHistory = MetricHistory()
        while !Task.isCancelled {
            await refresh()
            do { try await clock.sleep(for: interval) } catch { return }
        }
    }

    public func refresh() async {
        let sample = await monitor.sample()
        guard !Task.isCancelled else { return }

        let cpu = ProcessCPU.percentages(from: previous, to: sample)
        previous = sample
        let owners = processes.owners
        let summary = TaskSummary.make(sample: sample, cpu: cpu, owners: owners)

        rows = TaskTree.build(sample: sample, cpu: cpu, owners: owners)
        self.summary = summary
        sampledAt = sample.takenAt
        if let share = summary.cpuShare { cpuHistory.append(share, at: sample.takenAt) }
        memoryHistory.append(Double(summary.memory), at: sample.takenAt)
        threadHistory.append(Double(summary.threads), at: sample.takenAt)

        // A process that went away takes its selection with it.
        if let selection, row(selection) == nil { self.selection = nil }
    }

    // MARK: The table

    /// What the table shows: the rows in scope that match the filter, sorted
    /// among their siblings, and as deep as is open. A search opens
    /// everything, so that what it found is on screen.
    public var lines: [TaskLine] {
        let shown = TaskSort.apply(TaskFilter.apply(rows, scope: scope, text: filter), by: order)
        let isSearching = !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return TaskLine.flatten(shown, expanded: expanded, expandAll: isSearching)
    }

    /// Sorts by `column`; again, the other way. A new column starts with the
    /// biggest or the first: names and status A to Z, and the rest high to low.
    public func sort(by column: TaskSort.Column) {
        if order.column == column {
            order.ascending.toggle()
        } else {
            order = TaskSort.Order(column, ascending: column == .name || column == .status)
        }
    }

    public func toggleExpanded(_ id: TaskRow.ID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    // MARK: The selection

    public var selectedRow: TaskRow? { selection.flatMap(row(_:)) }

    /// The bottom bar's line for the selected row: "Syntax highlighting · 4
    /// processes · started 12m ago".
    public var selectionSummary: String? {
        guard let row = selectedRow else { return nil }
        var parts = [row.name]
        parts.append(TaskFormat.processes(row.processCount))
        if let started = row.startedAt, let now = sampledAt {
            let age = RelativeAge.short(from: started, now: now)
            parts.append(age == "now" ? "started just now" : "started \(age) ago")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// Whether Show session has a tab to bring forward: an agent session or a
    /// terminal, and not a process or a group.
    public var canShowSession: Bool {
        guard let id = selectedRow?.tabID else { return false }
        return processes.entry(id) != nil
    }

    /// Brings the selected tab forward in its window, and raises the window.
    public func showSelectedSession() {
        guard let id = selectedRow?.tabID else { return }
        processes.entry(id)?.show()
    }

    private func row(_ id: TaskRow.ID) -> TaskRow? {
        func find(in rows: [TaskRow]) -> TaskRow? {
            for row in rows {
                if row.id == id { return row }
                if let found = find(in: row.children) { return found }
            }
            return nil
        }
        return find(in: rows)
    }
}
