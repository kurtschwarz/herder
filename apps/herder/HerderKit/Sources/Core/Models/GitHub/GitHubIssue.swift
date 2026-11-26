import Foundation

/// An open issue, as far as a row in the "From issue" list needs it.
public struct GitHubIssue: Sendable, Equatable, Identifiable {
    public struct Label: Sendable, Equatable, Hashable {
        public var name: String
        /// Hex, without the `#`.
        public var color: String

        public init(name: String, color: String) {
            self.name = name
            self.color = color
        }
    }

    public var number: Int
    public var url: URL
    public var title: String
    public var labels: [Label]
    /// `nil` for an account that has been deleted.
    public var author: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var commentCount: Int

    public var id: Int { number }

    public init(
        number: Int,
        url: URL,
        title: String,
        labels: [Label] = [],
        author: String? = nil,
        createdAt: Date = .distantPast,
        updatedAt: Date = .distantPast,
        commentCount: Int = 0
    ) {
        self.number = number
        self.url = url
        self.title = title
        self.labels = labels
        self.author = author
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.commentCount = commentCount
    }

    /// What a session started from this issue remembers of it.
    public var link: LinkedIssue {
        LinkedIssue(number: number, title: title, url: url)
    }
}

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
