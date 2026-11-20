/// Where the app keeps the naming endpoint's API key: one Keychain item,
/// owned by the app.
public protocol NamingKeyVault: Sendable {
    /// `nil` when nothing is stored.
    func load() throws -> String?
    func save(_ key: String) throws
    /// Removing what is not there is not an error.
    func delete() throws
}
