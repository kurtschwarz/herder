import Foundation

/// A tracked file whose working copy differs from a revision, with how much.
public struct GitChangedFile: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case modified
        case added
        case deleted
        case renamed
    }

    /// Relative to the worktree, with `/` separators.
    public var path: String
    /// Where a renamed file was, relative to the worktree.
    public var previousPath: String?
    public var status: Status
    public var insertions: Int
    public var deletions: Int

    public init(path: String, previousPath: String? = nil, status: Status, insertions: Int = 0, deletions: Int = 0) {
        self.path = path
        self.previousPath = previousPath
        self.status = status
        self.insertions = insertions
        self.deletions = deletions
    }

    /// Reads `git diff --name-status -z` and `git diff --numstat -z`, both with
    /// renames detected, and joins them on the file's path.
    ///
    /// `-z` is the only safe way to read paths back. In `--name-status` a
    /// rename is `R100`, the old path and the new one; in `--numstat` it is
    /// the counts with an empty path, then the old path and the new one. A
    /// binary file counts as `-`, which reads as no lines. Sorted by path.
    public static func parse(nameStatus: String, numstat: String) -> [GitChangedFile] {
        var counts: [String: (Int, Int)] = [:]
        let stats = numstat.split(separator: "\0", omittingEmptySubsequences: false)
        var index = 0
        while index < stats.count {
            let fields = stats[index].split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            index += 1
            guard fields.count == 3 else { continue }
            var path = String(fields[2])
            if path.isEmpty, index + 1 < stats.count {
                path = String(stats[index + 1])
                index += 2
            }
            counts[path] = (Int(fields[0]) ?? 0, Int(fields[1]) ?? 0)
        }

        var files: [GitChangedFile] = []
        let names = nameStatus.split(separator: "\0", omittingEmptySubsequences: true)
        index = 0
        while index < names.count {
            let code = names[index]
            index += 1
            guard let letter = code.first, index < names.count else { continue }

            let status: Status
            var previous: String?
            var path = String(names[index])
            index += 1
            switch letter {
            case "A": status = .added
            case "D": status = .deleted
            case "R", "C":
                guard index < names.count else { continue }
                // A copy is a new file as far as the base is concerned.
                status = letter == "R" ? .renamed : .added
                if letter == "R" { previous = path }
                path = String(names[index])
                index += 1
            default: status = .modified
            }
            let (insertions, deletions) = counts[path] ?? (0, 0)
            files.append(GitChangedFile(
                path: path, previousPath: previous, status: status, insertions: insertions, deletions: deletions
            ))
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
