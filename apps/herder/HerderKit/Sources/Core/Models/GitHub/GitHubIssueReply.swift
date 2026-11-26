import Foundation

/// Which list of open issues to read.
public enum GitHubIssueTab: String, Sendable, Equatable, CaseIterable {
    case assigned
    case open
}

/// Whether herderd may answer from what it remembers.
public enum GitHubIssueFreshness: String, Sendable, Equatable {
    /// Only from memory: nothing is asked of GitHub.
    case cached
    /// Always from GitHub.
    case fresh
}

/// What asking GitHub about a repository's issues came to.
public enum GitHubIssueStatus: Sendable, Equatable {
    case ok
    /// The GitHub App is not installed on the repository, or the signed-in
    /// user cannot see it.
    case notAccessible
    /// GitHub refused the token, or herderd holds none.
    case unauthorized
    /// The App is installed, but the installation has not approved reading
    /// issues.
    case permissionMissing
    case error(String)
}

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

/// herderd's answer to a request for one issue.
public struct GitHubIssueDetailReply: Sendable, Equatable {
    public var status: GitHubIssueStatus
    /// `nil` when the repository has no such issue, which includes a number
    /// that is a pull request.
    public var detail: GitHubIssueDetail?

    public init(status: GitHubIssueStatus, detail: GitHubIssueDetail? = nil) {
        self.status = status
        self.detail = detail
    }
}
