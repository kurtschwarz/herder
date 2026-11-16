/// Finds herderd, starting it if it is not running, and says hello.
///
/// I/O and nothing else: what a reply means is ``DaemonWire``'s.
public protocol DaemonClient: Sendable {
    /// Reaches the daemon and completes the version handshake. Never throws:
    /// every way it can fail is a ``DaemonStatus`` the user can be shown.
    func connect() async -> DaemonStatus
}
