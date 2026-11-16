import Foundation
import Testing

@testable import Core

@Suite struct ShellLaunchTests {
    let directory = URL(filePath: "/tmp/work")
    let size = PTYSize(columns: 80, rows: 24)

    @Test func startsALoginShellInTheDirectory() {
        let spec = ShellLaunch.spec(environment: ["SHELL": "/bin/sh"], directory: directory, size: size)
        #expect(spec.executable == "/bin/sh")
        #expect(spec.arguments == ["/bin/sh", "-l"])
        #expect(spec.workingDirectory == directory)
        #expect(spec.size == size)
    }

    @Test func aCommandRunsThroughAnInteractiveLoginShell() {
        let spec = ShellLaunch.command(
            "exec opencode", environment: ["SHELL": "/bin/sh"], directory: directory, size: size
        )
        #expect(spec.executable == "/bin/sh")
        #expect(spec.arguments == ["/bin/sh", "-l", "-i", "-c", "exec opencode"])
        #expect(spec.workingDirectory == directory)
        #expect(spec.environment["TERM_PROGRAM"] == "Herder")
    }

    @Test func fallsBackToZshWhenThereIsNoShell() {
        #expect(ShellLaunch.spec(environment: [:], directory: directory, size: size).executable == "/bin/zsh")
        #expect(ShellLaunch.spec(environment: ["SHELL": ""], directory: directory, size: size).executable == "/bin/zsh")
    }

    @Test func fallsBackWhenTheShellIsNotAPathToAProgram() {
        #expect(ShellLaunch.spec(environment: ["SHELL": "zsh"], directory: directory, size: size).executable == "/bin/zsh")
        #expect(ShellLaunch.spec(environment: ["SHELL": "/no/such/shell"], directory: directory, size: size).executable == "/bin/zsh")
    }

    @Test func tellsTheShellWhatTerminalItIsIn() {
        let environment = ShellLaunch.spec(environment: [:], directory: directory, size: size).environment
        #expect(environment["TERM"] == "xterm-256color")
        #expect(environment["COLORTERM"] == "truecolor")
        #expect(environment["TERM_PROGRAM"] == "Herder")
    }

    @Test func overridesWhatTheAppWasLaunchedWith() {
        let environment = ShellLaunch.spec(
            environment: ["TERM": "dumb", "TERM_PROGRAM": "Apple_Terminal"], directory: directory, size: size
        ).environment
        #expect(environment["TERM"] == "xterm-256color")
        #expect(environment["TERM_PROGRAM"] == "Herder")
    }

    @Test func keepsTheRestOfTheEnvironment() {
        let environment = ShellLaunch.spec(
            environment: ["HOME": "/Users/x", "PATH": "/usr/bin"], directory: directory, size: size
        ).environment
        #expect(environment["HOME"] == "/Users/x")
        #expect(environment["PATH"] == "/usr/bin")
    }

    @Test func givesALocaleOnlyWhenThereIsNone() {
        #expect(ShellLaunch.spec(environment: [:], directory: directory, size: size).environment["LANG"] == "en_US.UTF-8")
        #expect(ShellLaunch.spec(environment: ["LANG": "fr_CA.UTF-8"], directory: directory, size: size).environment["LANG"] == "fr_CA.UTF-8")
    }
}

@Suite struct TerminalTitleTests {
    func process(_ commandLine: String, isShell: Bool = false) -> PTYProcess {
        PTYProcess(
            id: 1, name: String(commandLine.split(separator: " ").first ?? ""),
            commandLine: commandLine, isShell: isShell
        )
    }

    @Test func aShellInFrontIsNamedAfterItself() {
        #expect(TerminalTitle.make(for: process("zsh -l", isShell: true)) == "zsh")
    }

    @Test func aCommandIsShownAsTyped() {
        #expect(TerminalTitle.make(for: process("swift test")) == "swift test")
    }

    @Test func aLongCommandIsCutWithAnEllipsis() {
        let title = TerminalTitle.make(for: process("swift test --filter EditorStateTests --parallel"))
        #expect(title.count == TerminalTitle.maxLength)
        #expect(title.hasSuffix("\u{2026}"))
        #expect(title.hasPrefix("swift test --filter"))
    }

    @Test func aCommandExactlyAtTheLimitIsLeftAlone() {
        let command = String(repeating: "a", count: TerminalTitle.maxLength)
        #expect(TerminalTitle.make(for: process(command)) == command)
    }

    @Test func nothingKnownIsAPlaceholder() {
        #expect(TerminalTitle.make(for: nil) == "Terminal")
    }

    @Test func aNewlineInACommandIsASpace() {
        #expect(TerminalTitle.truncated("echo a\nb") == "echo a b")
    }
}
