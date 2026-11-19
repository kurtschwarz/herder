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
}
