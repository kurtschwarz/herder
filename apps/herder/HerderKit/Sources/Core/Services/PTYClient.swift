/// Starting processes attached to a pseudo-terminal.
public protocol PTYClient: Sendable {
    func spawn(_ spec: PTYSpec) async throws(PTYClientError) -> any PTYSession
}
