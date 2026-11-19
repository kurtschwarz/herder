/// Where the app keeps the GitHub tokens between launches: one item, owned by
/// the app. herderd never reads it.
public protocol GitHubTokenVault: Sendable {
    /// `nil` when nothing is stored.
    func load() throws -> GitHubTokens?
    func save(_ tokens: GitHubTokens) throws
    /// Removing what is not there is not an error.
    func delete() throws
}
