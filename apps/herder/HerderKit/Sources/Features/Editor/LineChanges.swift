import Foundation

/// Which lines of a text differ from a base text, sorted into the three kinds
/// the gutter marks.
///
/// Lines are counted from one, as the gutter numbers them. A text's lines are
/// what lie between newlines, so one ending in a newline has no empty line
/// after it.
nonisolated struct LineChanges: Equatable, Sendable {
    static let none = LineChanges()

    /// Anything bigger is not compared, so a large generated file cannot make
    /// typing lag.
    static let maxBytes = 1_000_000
    static let maxLines = 20_000

    /// Lines the current text has and the base does not.
    private(set) var added = IndexSet()

    /// Lines of the current text that replace lines of the base.
    private(set) var modified = IndexSet()

    /// Boundaries where lines were removed and nothing replaced them, each the
    /// number of the line above it: 0 is above the first line.
    private(set) var deleted = Set<Int>()

    var isEmpty: Bool { added.isEmpty && modified.isEmpty && deleted.isEmpty }

    private init() {}

    /// The lines of `current` that differ from `base`. Whitespace counts, as in
    /// git's default diff.
    ///
    /// Each hunk is sorted the way VS Code does it. Only insertions: each
    /// inserted line is added. Only removals: one deleted marker. Both: each
    /// inserted line is modified, with no deleted marker even when more lines
    /// went than came.
    init(base: String, current: String) {
        guard base.utf8.count <= Self.maxBytes, current.utf8.count <= Self.maxBytes else { return }
        let old = Self.lines(of: base)
        let new = Self.lines(of: current)
        guard old.count <= Self.maxLines, new.count <= Self.maxLines else { return }

        let difference = new.difference(from: old)
        var removals = Set<Int>()
        var insertions = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removals.insert(offset)
            case .insert(let offset, _, _): insertions.insert(offset)
            }
        }

        // The lines neither side changed pair off in order, so walking both
        // together finds each hunk as a run of removals and insertions between
        // two such pairs.
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < old.count || newIndex < new.count {
            guard removals.contains(oldIndex) || insertions.contains(newIndex) else {
                oldIndex += 1
                newIndex += 1
                continue
            }
            let firstNew = newIndex
            var removed = 0
            while removals.contains(oldIndex) {
                oldIndex += 1
                removed += 1
            }
            while insertions.contains(newIndex) { newIndex += 1 }

            let inserted = firstNew..<newIndex
            if inserted.isEmpty {
                deleted.insert(firstNew)
            } else if removed == 0 {
                added.insert(integersIn: (firstNew + 1)...newIndex)
            } else {
                modified.insert(integersIn: (firstNew + 1)...newIndex)
            }
        }
    }

    private static func lines(of text: String) -> [String] {
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }
}
