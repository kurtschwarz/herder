import Foundation

/// How a terminal's shell is started: which one, and what it is told about
/// where it is running.
///
/// Pure, so it is tested without starting anything. The environment comes in as
/// an argument because this is not where the app's own is read from.
public enum ShellLaunch {
    public static let fallbackShell = "/bin/zsh"

    /// A login shell in `directory`.
    ///
    /// Login, because Herder is started from the Dock with next to no
    /// environment: it is the user's profile that sets `PATH` and everything
    /// else a shell is expected to have, and copying it in would be a second
    /// place that has to agree with it.
    public static func spec(
        environment: [String: String],
        directory: URL,
        size: PTYSize
    ) -> PTYSpec {
        let shell = shell(from: environment)

        var environment = environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "Herder"
        // A shell that finds none draws its prompt's symbols wrongly. Finder
        // does not set one, and the terminal is always UTF-8.
        if environment["LANG"]?.isEmpty ?? true { environment["LANG"] = "en_US.UTF-8" }

        return PTYSpec(
            executable: shell,
            arguments: [shell, "-l"],
            environment: environment,
            workingDirectory: directory,
            size: size
        )
    }

    /// A login shell that runs `line` in place of itself and ends with it.
    ///
    /// Interactive as well as login: a person's `PATH` is as often set in the
    /// file an interactive shell reads as in the one a login shell does, and
    /// what is being started here is a program of theirs, found the way their
    /// own terminal would find it. `line` should `exec` its program, so that
    /// the shell is not left in front of it.
    public static func command(
        _ line: String,
        environment: [String: String],
        directory: URL,
        size: PTYSize
    ) -> PTYSpec {
        var spec = spec(environment: environment, directory: directory, size: size)
        spec.arguments = [spec.executable, "-l", "-i", "-c", line]
        return spec
    }

    /// `$SHELL` if it is a path to something, and zsh, which every Mac has,
    /// if not.
    public static func shell(from environment: [String: String]) -> String {
        guard let shell = environment["SHELL"], shell.hasPrefix("/"),
              FileManager.default.isExecutableFile(atPath: shell)
        else { return fallbackShell }
        return shell
    }
}
