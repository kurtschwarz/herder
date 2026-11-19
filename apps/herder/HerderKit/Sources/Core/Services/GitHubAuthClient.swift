import Foundation

/// Signing in to GitHub with the Herder GitHub App's device flow, and keeping
/// the resulting tokens fresh. Network and nothing else.
///
/// Lives in the app and not in herderd, which only ever holds the access
/// token it is handed. See ADR 0003.
public protocol GitHubAuthClient: Sendable {
    /// Starts a device flow.
    func requestDeviceCode() async throws -> GitHubDeviceCode

    /// Asks once whether the user has finished the flow `deviceCode` began.
    func poll(deviceCode: String) async throws -> GitHubDevicePoll

    /// Trades a refresh token for a new pair of tokens. GitHub refuses a
    /// refresh token it has already honoured, so the caller must save what
    /// this returns before it does anything else.
    func refresh(using refreshToken: String) async throws -> GitHubTokens
}
