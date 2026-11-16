/// What a daemon said about itself in its welcome.
public struct DaemonInfo: Equatable, Sendable {
    public var daemonVersion: String
    /// The protocol version every later message on the connection uses.
    public var protocolVersion: Int
    /// The machine it runs on. `local` is this one.
    public var host: String

    public init(daemonVersion: String, protocolVersion: Int, host: String) {
        self.daemonVersion = daemonVersion
        self.protocolVersion = protocolVersion
        self.host = host
    }
}
