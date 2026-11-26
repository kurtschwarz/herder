import Foundation

/// Reads a repository's open issues, through herderd. The folder is any one
/// of the repository's, whose `origin` says which repository.
///
/// Neither call throws for GitHub's refusals: those are a ``GitHubIssueStatus``
/// in the answer. They throw only when herderd cannot be asked.
public protocol GitHubIssuesClient: Sendable {
    func list(
        at path: String, tab: GitHubIssueTab, freshness: GitHubIssueFreshness
    ) async throws -> GitHubIssueList

    /// One issue with its body and comments, never from memory.
    func detail(at path: String, number: Int) async throws -> GitHubIssueDetailReply
}
