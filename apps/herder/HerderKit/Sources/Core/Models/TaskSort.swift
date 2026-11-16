import Foundation

/// Sorting the Task Manager's rows among their siblings.
public enum TaskSort {
    public enum Column: Sendable, CaseIterable {
        case name
        case status
        case cpu
        case memory
        case threads
        case processes
        case uptime
    }

    public struct Order: Sendable, Equatable {
        public var column: Column
        public var ascending: Bool

        public init(_ column: Column, ascending: Bool) {
            self.column = column
            self.ascending = ascending
        }

        /// What the table opens with: the busiest first.
        public static let `default` = Order(.cpu, ascending: false)
    }

    /// `rows` sorted, and each row's children, and theirs. A group and
    /// Herder's own row hold the place they were in, and only the rows around
    /// them change places: the groups never reorder.
    public static func apply(_ rows: [TaskRow], by order: Order) -> [TaskRow] {
        let slots = rows.indices.filter { !rows[$0].isPinned }
        let sorted = slots.map { (index: $0, row: rows[$0]) }.sorted { lhs, rhs in
            switch compare(lhs.row, rhs.row, by: order.column) {
            case .orderedAscending: order.ascending
            case .orderedDescending: !order.ascending
            case .orderedSame: lhs.index < rhs.index
            }
        }

        var result = rows
        for (slot, entry) in zip(slots, sorted) { result[slot] = entry.row }
        return result.map { row in
            var row = row
            row.children = apply(row.children, by: order)
            return row
        }
    }

    private static func compare(_ lhs: TaskRow, _ rhs: TaskRow, by column: Column) -> ComparisonResult {
        switch column {
        case .name: lhs.name.localizedStandardCompare(rhs.name)
        case .status: compare(rank(lhs.status), rank(rhs.status))
        // No rate yet is less than any rate.
        case .cpu: compare(lhs.cpu ?? -1, rhs.cpu ?? -1)
        case .memory: compare(lhs.memory, rhs.memory)
        case .threads: compare(lhs.threads, rhs.threads)
        case .processes: compare(lhs.processCount, rhs.processCount)
        // The longest running is the one that started first; none is the least.
        case .uptime: compare(lhs.startedAt.map { -$0.timeIntervalSince1970 } ?? -.infinity,
                              rhs.startedAt.map { -$0.timeIntervalSince1970 } ?? -.infinity)
        }
    }

    private static func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        lhs < rhs ? .orderedAscending : lhs > rhs ? .orderedDescending : .orderedSame
    }

    /// Needing the person first, then work, then rest.
    private static func rank(_ status: TaskRow.Status) -> Int {
        switch status {
        case .needsYou: 0
        case .working: 1
        case .running: 2
        case .starting: 3
        case .idle: 4
        case .sleeping: 5
        case .done: 6
        case .failed: 7
        case .none: 8
        }
    }
}
