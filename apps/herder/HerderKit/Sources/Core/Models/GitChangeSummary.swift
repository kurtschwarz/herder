import Foundation

/// How many lines a worktree has inserted and deleted, as `git diff
/// --shortstat` counts them.
public struct GitChangeSummary: Equatable, Sendable {
    public var insertions: Int
    public var deletions: Int

    public init(insertions: Int, deletions: Int) {
        self.insertions = insertions
        self.deletions = deletions
    }

    /// Reads `git diff --shortstat`: ` 3 files changed, 107 insertions(+), 19
    /// deletions(-)`. Either count is left out when it is zero, and the whole
    /// line when nothing changed, so anything with no count in it reads as no
    /// change.
    public static func parse(shortstat output: String) -> GitChangeSummary {
        var summary = GitChangeSummary(insertions: 0, deletions: 0)
        for part in output.split(separator: ",") {
            let words = part.split(whereSeparator: \.isWhitespace)
            guard words.count >= 2, let count = Int(words[0]) else { continue }
            if words[1].hasPrefix("insertion") {
                summary.insertions = count
            } else if words[1].hasPrefix("deletion") {
                summary.deletions = count
            }
        }
        return summary
    }
}
