/// GitHub's answer to one poll of a device flow.
public enum GitHubDevicePoll: Equatable, Sendable {
    /// The user has not finished yet.
    case pending
    /// Polling too fast: wait longer between polls.
    case slowDown
    case signedIn(GitHubTokens)
    /// The user refused on GitHub.
    case denied
    /// The code ran out before the user used it.
    case expired
}
