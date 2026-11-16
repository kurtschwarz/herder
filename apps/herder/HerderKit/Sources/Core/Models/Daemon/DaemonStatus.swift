/// Where the app stands with herderd, for Settings to show.
public enum DaemonStatus: Equatable, Sendable {
    /// Looking for the daemon, starting it, or waiting for its answer.
    case connecting

    /// The daemon answered and the two share a protocol version.
    case connected(DaemonInfo)

    /// The daemon is running and speaks no version the app does. Shown, not
    /// ignored: the app cannot use it, and killing it would end its sessions.
    case incompatible(daemonVersion: String, supports: ClosedRange<Int>, app: ClosedRange<Int>)

    /// No daemon could be reached or started.
    case unavailable(reason: String)
}
