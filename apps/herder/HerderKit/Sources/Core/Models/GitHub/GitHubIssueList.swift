import Foundation

/// herderd's answer to an issue query.
public struct GitHubIssueList: Sendable, Equatable {
    /// `owner/name`, as `origin` names it. `nil` when `origin` is not on
    /// github.com.
    public var repository: String?
    public var status: GitHubIssueStatus
    /// Most recently updated first.
    public var issues: [GitHubIssue]
    /// When GitHub said so. `nil` when there is nothing to show: a cached
    /// query that found nothing remembered.
    public var fetchedAt: Date?
    public var assignedCount: Int?
    public var openCount: Int?

    public init(
        repository: String?,
        status: GitHubIssueStatus,
        issues: [GitHubIssue] = [],
        fetchedAt: Date? = nil,
        assignedCount: Int? = nil,
        openCount: Int? = nil
    ) {
        self.repository = repository
        self.status = status
        self.issues = issues
        self.fetchedAt = fetchedAt
        self.assignedCount = assignedCount
        self.openCount = openCount
    }
}
