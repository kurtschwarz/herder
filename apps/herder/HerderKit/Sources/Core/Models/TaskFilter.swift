import Foundation

/// Narrowing the Task Manager's rows: to one half of the app, and to what a
/// typed word matches.
public enum TaskFilter {
    public enum Scope: Sendable, CaseIterable {
        case all
        case agents
        case herder
    }

    /// `rows` limited to `scope`, and then to what `text` finds.
    ///
    /// A row matches on its name, its title, its worktree, its branch or its
    /// pid. A row that matches stays with everything under it, and a row with
    /// a match somewhere under it stays so that the match can be reached. A
    /// group is never a match of its own, and goes when nothing under it is.
    public static func apply(_ rows: [TaskRow], scope: Scope, text: String) -> [TaskRow] {
        let scoped = rows.filter { row in
            switch scope {
            case .all: true
            case .agents: row.id == .agentSessions
            case .herder: row.id == .herder
            }
        }
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return scoped }
        return scoped.compactMap { prune($0, query: query) }
    }

    private static func prune(_ row: TaskRow, query: String) -> TaskRow? {
        if !row.isGroup, matches(row, query) { return row }
        let children = row.children.compactMap { prune($0, query: query) }
        guard !children.isEmpty else { return nil }
        var row = row
        row.children = children
        return row
    }

    private static func matches(_ row: TaskRow, _ query: String) -> Bool {
        ([row.name] + row.searchTerms).contains { $0.range(of: query, options: .caseInsensitive) != nil }
    }
}
