import Foundation

/// What to run in a pseudo-terminal, and how.
///
/// The environment is the whole environment, not additions to the caller's:
/// the child gets exactly this, so what a shell inherits is decided where the
/// spec is made rather than by whatever the app was launched with.
public struct PTYSpec: Sendable, Equatable {
    public var executable: String

    /// What the child sees as `argv`, `argv[0]` included. A login shell is one
    /// whose `argv[0]` starts with a dash, so this is not always the path.
    public var arguments: [String]
    public var environment: [String: String]
    public var workingDirectory: URL
    public var size: PTYSize

    public init(
        executable: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL,
        size: PTYSize
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.size = size
    }
}
