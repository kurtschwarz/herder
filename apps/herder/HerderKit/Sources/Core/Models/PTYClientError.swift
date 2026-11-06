/// Why a terminal could not be started.
public enum PTYClientError: Error, Equatable, Sendable {
    /// The system would not make a pseudo-terminal. Carries `errno`.
    case openFailed(Int32)

    /// The program could not be started: it is missing, not executable, or the
    /// working directory is gone. Carries the error from `posix_spawn`.
    case spawnFailed(Int32)
}
