import Foundation

/// A device flow that has started: the code the user types at
/// `verificationURL`, and what the app polls with while they do.
public struct GitHubDeviceCode: Equatable, Sendable {
    /// What the app polls with. Never shown.
    public var deviceCode: String
    /// What the user types, e.g. `WDJB-MJHT`.
    public var userCode: String
    public var verificationURL: URL
    /// How long the codes last.
    public var expiresIn: Duration
    /// The least time between polls.
    public var interval: Duration

    public init(deviceCode: String, userCode: String, verificationURL: URL, expiresIn: Duration, interval: Duration) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.expiresIn = expiresIn
        self.interval = interval
    }
}
