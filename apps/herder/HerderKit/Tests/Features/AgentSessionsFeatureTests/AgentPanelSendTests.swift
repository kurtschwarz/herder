import Core
import Foundation
import TestSupport
import Testing

@testable import AgentSessionsFeature

/// What the selection prompt's text does to an agent's terminal, against a PTY
/// the test plays both ends of.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AgentPanelSendTests {
    let base = AgentPanelModelTests()

    @Test func textIsPastedWithoutReturnUnlessSubmitted() async throws {
        let (model, _, _) = try await base.shown(sessions: 1)
        let id = try #require(model.activeTab?.id)
        let session = try #require(base.pty.sessions.last)

        // The agent asks for bracketed paste, as the ones Herder runs do.
        session.emit("\u{1B}[?2004h")
        let screen = try #require(model.activeTab?.screen)
        try await eventually("the terminal turns bracketed paste on") { screen.isBracketedPasteOn }

        model.send("@Foo.swift#L1-2\n\nwhy?", to: id, submit: false)

        try await eventually("the text arrives") { session.input.hasSuffix("\u{1B}[201~") }
        // Inside the brackets, so the agent does not take them for Return.
        #expect(session.input == "\u{1B}[200~@Foo.swift#L1-2\r\rwhy?\u{1B}[201~")
    }

    @Test func returnFollowsThePasteWhenSubmitted() async throws {
        let (model, _, _) = try await base.shown(sessions: 1)
        let id = try #require(model.activeTab?.id)
        let session = try #require(base.pty.sessions.last)

        model.send("hello", to: id, submit: true)

        try await eventually("the text and Return arrive") { session.input.hasSuffix("\r") }
        #expect(session.input.hasPrefix("hello"))
    }

    @Test func anotherTabIsAddressedById() async throws {
        let (model, _, _) = try await base.shown(sessions: 2)
        let first = try #require(model.tabs.first?.id)
        let sessions = base.pty.sessions

        model.send("for the first", to: first, submit: false)

        try await eventually("the text arrives") { sessions[0].input.contains("for the first") }
        #expect(sessions[1].input.isEmpty)
    }

    @Test func aSessionThatIsNotRunningIsLeftAlone() async throws {
        let (model, _, _) = try await base.shown(sessions: 1)
        let id = try #require(model.activeTab?.id)
        let session = try #require(base.pty.sessions.last)
        session.exit(with: 1)
        try await eventually("the tab sees it exit") { model.activeTab?.phase != .running }

        model.send("too late", to: id, submit: true)
        try await Task.sleep(for: .milliseconds(50))

        #expect(session.input.isEmpty)
    }
}
