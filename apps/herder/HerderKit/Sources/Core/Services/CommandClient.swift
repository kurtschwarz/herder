import Foundation

/// Running a command line and reading what it prints.
///
/// For asking a program a question, such as which session an agent last
/// started, not for anything a person watches: that is a ``PTYClient``.
public protocol CommandClient: Sendable {
    /// Runs `line` through the user's login shell in `directory` and returns
    /// what it wrote to standard output, or `nil` if it could not be run, did
    /// not exit with 0, or took longer than a few seconds.
    func output(of line: String, in directory: URL) async -> String?
}
