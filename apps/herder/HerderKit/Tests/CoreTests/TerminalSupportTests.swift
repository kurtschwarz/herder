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

@Suite struct HomeRelativePathTests {
    let home = URL(filePath: "/Users/kurt", directoryHint: .isDirectory)

    @Test func theHomeFolderIsATilde() {
        #expect(HomeRelativePath.label(for: home, home: home) == "~")
    }

    @Test func aFolderUnderItIsRelative() {
        #expect(HomeRelativePath.label(for: URL(filePath: "/Users/kurt/dev/app/"), home: home) == "~/dev/app")
    }

    @Test func aFolderOutsideItIsLeftAlone() {
        #expect(HomeRelativePath.label(for: URL(filePath: "/usr/local"), home: home) == "/usr/local")
    }

    @Test func aSiblingWithTheSamePrefixIsNotUnderIt() {
        #expect(HomeRelativePath.label(for: URL(filePath: "/Users/kurtis/dev"), home: home) == "/Users/kurtis/dev")
    }
}

@Suite struct PanelHeightTests {
    let limits = PanelHeight.Limits(defaultHeight: 240, minimumPanel: 120, minimumEditor: 160)

    @Test func neverDraggedTakesTheDefault() {
        #expect(PanelHeight.resolved(nil, in: 800, limits: limits) == 240)
    }

    @Test func aStoredHeightIsKept() {
        #expect(PanelHeight.resolved(300, in: 800, limits: limits) == 300)
    }

    @Test func itIsHeldAboveItsMinimum() {
        #expect(PanelHeight.clamp(40, in: 800, limits: limits) == 120)
    }

    @Test func itLeavesTheEditorItsMinimum() {
        #expect(PanelHeight.clamp(700, in: 800, limits: limits) == 640)
    }

    @Test func aShortWindowGivesThePanelItsMinimumAnyway() {
        #expect(PanelHeight.resolved(300, in: 200, limits: limits) == 120)
    }

    @Test func squeezingDoesNotForgetWhatWasStored() {
        #expect(PanelHeight.resolved(500, in: 400, limits: limits) == 240)
        #expect(PanelHeight.resolved(500, in: 900, limits: limits) == 500)
    }
}
