import Foundation

/// Whether herderd may answer from what it remembers.
public enum GitHubIssueFreshness: String, Sendable, Equatable {
    /// Only from memory: nothing is asked of GitHub.
    case cached
    /// Always from GitHub.
    case fresh
}
