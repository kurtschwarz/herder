import Foundation

/// What signing in to GitHub gives the app: a short-lived access token, the
/// refresh token that replaces it, and when each stops working.
///
/// The whole value is one Keychain item. It never prints its tokens, so a log
/// line or a failed test cannot leak them.
public struct GitHubTokens: Equatable, Sendable, Codable, CustomStringConvertible, CustomDebugStringConvertible {
    public var accessToken: String
    public var refreshToken: String
    public var accessExpiresAt: Date
    public var refreshExpiresAt: Date

    public init(accessToken: String, refreshToken: String, accessExpiresAt: Date, refreshExpiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessExpiresAt = accessExpiresAt
        self.refreshExpiresAt = refreshExpiresAt
    }

    public var description: String {
        "GitHubTokens(access expires \(accessExpiresAt), refresh expires \(refreshExpiresAt))"
    }

    public var debugDescription: String { description }
}
