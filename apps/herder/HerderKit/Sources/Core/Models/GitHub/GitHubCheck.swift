/// What herderd found when it asked GitHub who the token belongs to.
public enum GitHubCheck: Equatable, Sendable {
    /// The daemon holds no token.
    case notConnected
    /// The token works, and belongs to `login`.
    case ok(login: String)
    /// GitHub refused the token.
    case unauthorized
    /// GitHub could not be asked, or the daemon could not be reached.
    case error(String)
}
