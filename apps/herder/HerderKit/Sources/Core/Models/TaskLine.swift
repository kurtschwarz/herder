import Foundation

/// A row as the table draws it: where it is in the tree, and whether what is
/// under it is showing.
public struct TaskLine: Identifiable, Sendable, Equatable {
    public var row: TaskRow
    public var depth: Int
    public var isExpanded: Bool

    public var id: TaskRow.ID { row.id }
    public var hasChildren: Bool { !row.children.isEmpty }

    /// `rows` and, under each one in `expanded`, its children, in order. With
    /// `expandAll` every row is open, which is how a search shows its matches.
    public static func flatten(_ rows: [TaskRow], expanded: Set<TaskRow.ID>, expandAll: Bool = false, depth: Int = 0) -> [TaskLine] {
        rows.flatMap { row -> [TaskLine] in
            let isExpanded = expandAll || expanded.contains(row.id)
            let line = TaskLine(row: row, depth: depth, isExpanded: isExpanded)
            guard isExpanded else { return [line] }
            return [line] + flatten(row.children, expanded: expanded, expandAll: expandAll, depth: depth + 1)
        }
    }
}
