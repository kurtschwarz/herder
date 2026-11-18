import Foundation

/// One commit, as far as a list of them needs: which, what it says, and when.
public struct GitCommit: Equatable, Sendable {
    public var sha: String
    public var subject: String
    public var date: Date

    public init(sha: String, subject: String, date: Date) {
        self.sha = sha
        self.subject = subject
        self.date = date
    }

    /// The first seven characters, which is what a person reads and types.
    public var shortSHA: String { String(sha.prefix(7)) }

    /// Reads `git log --format=%H%x00%ct%x00%s`, one commit per line.
    public static func parse(_ output: String) -> [GitCommit] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\0", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, let seconds = TimeInterval(parts[1]) else { return nil }
            return GitCommit(sha: String(parts[0]), subject: String(parts[2]), date: Date(timeIntervalSince1970: seconds))
        }
    }
}
