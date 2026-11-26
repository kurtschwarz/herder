import Foundation

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
