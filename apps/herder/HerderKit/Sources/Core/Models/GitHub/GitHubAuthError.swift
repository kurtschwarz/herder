public enum GitHubAuthError: Error, Equatable, Sendable {
    /// This build has no GitHub App client ID, so there is nothing to sign in to.
    case notConfigured
    /// GitHub refused the refresh token: it expired, was revoked or was used
    /// already. Only signing in again helps.
    case refreshTokenRejected
    /// GitHub could not be reached. Asking again later may work.
    case network(String)
    /// GitHub answered with something the app does not understand.
    case unexpected(String)
}
