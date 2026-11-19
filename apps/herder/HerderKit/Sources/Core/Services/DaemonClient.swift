import Foundation

/// Finds herderd, starting it if it is not running, and says hello.
///
/// I/O and nothing else: what a reply means is ``DaemonWire``'s.
public protocol DaemonClient: Sendable {
    /// Reaches the daemon and completes the version handshake. Never throws:
    /// every way it can fail is a ``DaemonStatus`` the user can be shown.
    func connect() async -> DaemonStatus

    /// Sends one request and returns the daemon's one reply, both the payload
    /// of a frame (see ``DaemonWire``). Reaches or starts the daemon first, as
    /// ``connect()`` does, and throws when it cannot.
    func request(_ payload: Data) async throws -> Data
}
