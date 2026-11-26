import Foundation

/// An issue with what an agent starts from: its body and its latest comments.
public struct GitHubIssueDetail: Sendable, Equatable {
    public struct Comment: Sendable, Equatable {
        /// `nil` for an account that has been deleted.
        public var author: String?
        public var body: String
        public var createdAt: Date

        public init(author: String?, body: String, createdAt: Date = .distantPast) {
            self.author = author
            self.body = body
            self.createdAt = createdAt
        }
    }

    public var issue: GitHubIssue
    public var body: String
    /// Oldest first.
    public var comments: [Comment]

    public init(issue: GitHubIssue, body: String, comments: [Comment] = []) {
        self.issue = issue
        self.body = body
        self.comments = comments
    }
}
