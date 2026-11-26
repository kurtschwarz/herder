import Foundation

/// Which list of open issues to read.
public enum GitHubIssueTab: String, Sendable, Equatable, CaseIterable {
    case assigned
    case open
}
