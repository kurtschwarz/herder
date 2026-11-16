import Core
import Foundation

/// One row of the Task Manager's table: a group, a tab, or a process, with
/// what it and everything under it add up to.
///
/// CPU, memory, threads and the process count are all for the row's whole
/// subtree, so a collapsed row accounts for everything it hides and a group
/// header is a subtotal.
struct TaskRow: Identifiable, Sendable, Equatable {
    enum ID: Hashable, Sendable {
        case agentSessions
        case herder
        case terminals
        case other
        /// A tab, whichever kind: the id its registry entry has.
        case tab(UUID)
        case process(ProcessKey)
    }

    enum Kind: Sendable, Equatable {
        /// A heading. Never moves when rows are sorted.
        case group
        case session
        case terminal
        /// Herder's own process. Never moves when rows are sorted.
        case herder
        case process
    }

    enum Status: Sendable, Equatable {
        case working
        case needsYou
        case idle
        /// Remembered from before, and not started until its tab is shown.
        case paused
        case starting
        case failed
        /// The agent has exited and its tab is still open.
        case done
        case running
        case sleeping
        case none
    }

    var id: ID
    var kind: Kind
    var name: String

    /// A dim second line: the worktree, the pid, or what kind of row it is.
    var subtitle: String?

    /// The full command line, for a tooltip.
    var help: String?
    var status: Status

    /// Percent of one core. `nil` until there are two samples to tell it by.
    var cpu: Double?
    var memory: UInt64
    var threads: Int
    var processCount: Int

    /// When the row's process started. `nil` for a group, and for a tab whose
    /// process is gone.
    var startedAt: Date?

    var pid: Int32?

    /// What the filter looks at, besides the name.
    var searchTerms: [String]

    var children: [TaskRow]

    init(
        id: ID,
        kind: Kind,
        name: String,
        subtitle: String? = nil,
        help: String? = nil,
        status: Status = .none,
        cpu: Double? = nil,
        memory: UInt64 = 0,
        threads: Int = 0,
        processCount: Int = 0,
        startedAt: Date? = nil,
        pid: Int32? = nil,
        searchTerms: [String] = [],
        children: [TaskRow] = []
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.subtitle = subtitle
        self.help = help
        self.status = status
        self.cpu = cpu
        self.memory = memory
        self.threads = threads
        self.processCount = processCount
        self.startedAt = startedAt
        self.pid = pid
        self.searchTerms = searchTerms
        self.children = children
    }

    /// A heading over `children`, with their totals.
    static func group(_ id: ID, name: String, children: [TaskRow]) -> TaskRow {
        var row = TaskRow(id: id, kind: .group, name: name, children: children)
        row.addTotals(of: children)
        return row
    }

    /// Takes on the totals of `rows`. A row none of whose rows has a rate has
    /// none itself.
    mutating func addTotals(of rows: [TaskRow]) {
        for child in rows {
            if let rate = child.cpu { cpu = (cpu ?? 0) + rate }
            memory += child.memory
            threads += child.threads
            processCount += child.processCount
        }
    }

    var isGroup: Bool { kind == .group }

    /// Whether this row stays where it is when its siblings are sorted.
    var isPinned: Bool { kind == .group || kind == .herder }

    /// The tab this row stands for, if it is one.
    var tabID: UUID? {
        if case .tab(let id) = id { id } else { nil }
    }
}
