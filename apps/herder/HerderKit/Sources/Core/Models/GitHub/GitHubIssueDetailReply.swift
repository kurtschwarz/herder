import Foundation

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
