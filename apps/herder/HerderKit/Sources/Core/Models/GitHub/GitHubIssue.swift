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
