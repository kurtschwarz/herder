import Foundation

/// Where the app stands with GitHub, for Settings to show.
public enum GitHubConnectionState: Equatable, Sendable {
    /// Reading the Keychain and asking GitHub, at launch.
    case checking

    case notConnected

    /// The user has to enter `code.userCode` at `code.verificationURL`.
    case signingIn(GitHubDeviceCode)

    case connected(login: String)

    /// Signed in, but GitHub or herderd could not confirm it. `reason` says why.
    case unverified(reason: String)

    /// The refresh token is no longer good: the user has to sign in again.
    case reconnect
}
