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

    @Test func aShellsDirectoryIsKept() async throws {
        let (screen, session) = make()
        session.emit("\u{1b}]7;file://host/tmp/work\u{7}")
        try await eventually("the directory") { screen.reportedDirectory != nil }
        #expect(screen.reportedDirectory?.path(percentEncoded: false) == "/tmp/work")
    }
}
