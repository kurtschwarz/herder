import Core
import Foundation
import TestSupport
import Testing

@testable import TerminalUI

/// The screen between a process and a view, against a session the test plays
/// the other end of.
@Suite(.timeLimit(.minutes(1))) struct TerminalScreenTests {
    /// A screen and the session behind it, since the session is the half the
    /// test drives.
    func make() -> (TerminalScreen, StubPTYSession) {
        let session = StubPTYSession(spec: PTYSpec(
            executable: "/bin/zsh", arguments: ["-zsh"], environment: [:],
            workingDirectory: URL(filePath: "/tmp"), size: PTYSize(columns: 40, rows: 10)
        ))
        return (TerminalScreen(session: session, size: PTYSize(columns: 40, rows: 10)), session)
    }

    func eventually(_ what: String, _ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("never happened: \(what)")
    }

    func firstLine(of screen: TerminalScreen) -> String {
        screen.emulator.cells.first?.map { $0.text.isEmpty ? " " : $0.text }.joined().replacing(/\s+$/, with: "") ?? ""
    }

    @Test func whatTheProcessWritesAppearsOnTheScreen() async throws {
        let (screen, session) = make()
        session.emit("hello")
        try await eventually("the text") { firstLine(of: screen) == "hello" }
    }

    @Test func whatIsTypedGoesToTheProcess() async throws {
        let (screen, session) = make()
        screen.send(text: "ls\r")
        try await eventually("the input") { session.input == "ls\r" }
    }

    @Test func returnIsToldAndOtherInputIsNot() async throws {
        let (screen, _) = make()
        var submits = 0
        screen.onSubmit = { submits += 1 }

        screen.send(text: "ls")
        screen.paste("a\rb")
        #expect(submits == 0)

        screen.send(text: "\r")
        #expect(submits == 1)
    }

    @Test func inputArrivesInTheOrderItWasGiven() async throws {
        let (screen, session) = make()
        let expected = (0..<200).map { "\($0)," }.joined()
        for index in 0..<200 { screen.send(text: "\(index),") }
        try await eventually("all of it") { session.input == expected }
    }

    @Test func aQueryIsAnsweredToTheProcess() async throws {
        let (screen, session) = make()
        _ = screen
        session.emit("\u{1b}[5n")
        try await eventually("the reply") { session.input == "\u{1b}[0n" }
    }

    @Test func aPasteIsBracketedWhenTheProgramAskedForThat() async throws {
        let (screen, session) = make()
        session.emit("\u{1b}[?2004h")
        try await eventually("the mode") { !screen.emulator.encodePaste("x").elementsEqual(Data("x".utf8)) }
        screen.paste("ls")
        try await eventually("the paste") { session.input == "\u{1b}[200~ls\u{1b}[201~" }
    }

    @Test func theScreenKnowsWhenTheOutputEnded() async throws {
        let (screen, session) = make()
        #expect(!screen.hasEnded)
        session.exit(with: 0)
        try await eventually("the end") { screen.hasEnded }
    }

    @Test func aLineOfOurOwnIsShownAndNotSent() async throws {
        let (screen, session) = make()
        session.emit("done")
        screen.announce("[Process exited with code 1]")
        try await eventually("the line") {
            screen.emulator.cells.contains { $0.map(\.text).joined().contains("[Process exited with code 1]") }
        }
        #expect(session.input.isEmpty)
    }

    @Test func aBellIsCounted() async throws {
        let (screen, session) = make()
        session.emit("\u{7}")
        try await eventually("the bell") { screen.bellCount == 1 }
    }

    @Test func aResizeReachesTheProcess() async throws {
        let (screen, session) = make()
        screen.resize(columns: 100, rows: 30, cellWidth: 7, cellHeight: 15)
        #expect(screen.emulator.columns == 100)
        try await eventually("the size") { session.size == PTYSize(columns: 100, rows: 30) }
    }

    @Test func aResizeToTheSameSizeSaysNothing() async throws {
        let (screen, session) = make()
        screen.resize(columns: 40, rows: 10, cellWidth: 7, cellHeight: 15)
        try await Task.sleep(for: .milliseconds(30))
        #expect(session.size == PTYSize(columns: 40, rows: 10))
    }

    @Test func typingBringsYouBackToTheBottom() async throws {
        let (screen, session) = make()
        session.emit((1...40).map { "line\($0)" }.joined(separator: "\r\n"))
        try await eventually("the output") { screen.emulator.scroll.total > 10 }
        screen.refresh()
        screen.emulator.scroll(by: -15)
        #expect(!screen.emulator.scroll.isAtBottom)

        screen.send(text: "x")
        #expect(screen.emulator.scroll.isAtBottom)
    }

    // MARK: Program status (OSC 7501)

    func status(_ fields: String) -> String { "\u{1b}]7501;\(fields)\u{7}" }

    func base64(_ text: String) -> String { Data(text.utf8).base64EncodedString() }

    @Test func aProgramStatusIsKeptDecoded() async throws {
        let (screen, session) = make()
        session.emit(status("state=blocked:kind=permission:app=opencode:msg=\(base64("Edit main.swift?"))"))
        try await eventually("the record") { !screen.programStatuses.isEmpty }
        #expect(screen.programStatuses == [
            ProgramStatus(state: .blocked, need: .permission, app: "opencode", message: "Edit main.swift?"),
        ])
    }

    @Test func aReportReplacesItsRecordWhole() async throws {
        let (screen, session) = make()
        session.emit(status("state=working:app=opencode:msg=\(base64("Thinking"))"))
        session.emit(status("state=idle"))
        try await eventually("the second report") { screen.programStatuses.first?.state == .idle }
        #expect(screen.programStatuses == [ProgramStatus(state: .idle)])
    }

    @Test func aRecordTakesItsAppFromAboveAndAClearTakesWhatIsBeneath() async throws {
        let (screen, session) = make()
        session.emit(status("state=working:app=deploy"))
        session.emit(status("state=working:id=us-east"))
        session.emit(status("state=working:id=us-east/db"))
        session.emit(status("state=working:id=eu-west"))
        try await eventually("every record") { screen.programStatuses.count == 4 }
        #expect(screen.programStatuses.map(\.app) == ["deploy", "deploy", "deploy", "deploy"])

        session.emit(status("state=clear:id=us-east"))
        try await eventually("the clear") { screen.programStatuses.count == 2 }
        #expect(screen.programStatuses.map(\.id) == ["", "eu-west"])

        session.emit(status("state=clear"))
        try await eventually("the clear of everything") { screen.programStatuses.isEmpty }
    }

    @Test func invisibleFormattingIsTakenOutOfAStatus() async throws {
        let (screen, session) = make()
        session.emit(status("state=blocked:msg=\(base64("Approve\u{202E}txt.exe"))"))
        try await eventually("the record") { !screen.programStatuses.isEmpty }
        #expect(screen.programStatuses.first?.message == "Approvetxt.exe")
    }

    @Test func aProgramThatAsksIsToldStatusIsUnderstood() async throws {
        let (screen, session) = make()
        _ = screen
        session.emit(status("?"))
        try await eventually("the reply") { session.input.hasPrefix("\u{1b}]7501;?") }
    }

    @Test func whatWasWorkingOrWaitingGoesWhenTheProgramEnds() async throws {
        let (screen, session) = make()
        session.emit(status("state=working:id=build"))
        session.emit(status("state=blocked:id=deploy"))
        session.emit(status("state=done:id=test"))
        try await eventually("the records") { screen.programStatuses.count == 3 }
        session.exit(with: 0)
        try await eventually("the end") { screen.hasEnded }
        #expect(screen.programStatuses.map(\.id) == ["test"])
    }

    @Test func aShellsDirectoryIsKept() async throws {
        let (screen, session) = make()
        session.emit("\u{1b}]7;file://host/tmp/work\u{7}")
        try await eventually("the directory") { screen.reportedDirectory != nil }
        #expect(screen.reportedDirectory?.path(percentEncoded: false) == "/tmp/work")
    }
}
