public enum GitClientError: Error, Equatable {
    /// `git` ran and refused, with what it said.
    case commandFailed(String)
}
