import Foundation

/// Ends agents an earlier run of Herder left behind. See ``AgentMark``.
public protocol LeftoverAgentClient: Sendable {
    /// Asks each leftover to end, and makes it a little later if it has not.
    /// Returns once they have all been dealt with.
    func endLeftovers() async
}
