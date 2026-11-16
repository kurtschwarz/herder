import Foundation
import Testing

import Core

@testable import TaskManagerFeature

/// Which processes belong to which tab, and what is left over.
@Suite struct TaskTreeTests {
    typealias F = ProcessFixtures

    func build(
        _ sample: ProcessSample,
        cpu: [ProcessKey: Double] = [:],
        owners: [ProcessOwner] = []
    ) -> [TaskRow] {
        TaskTree.build(sample: sample, cpu: cpu, owners: owners)
    }

    func ids(_ rows: [TaskRow]) -> [TaskRow.ID] { rows.map(\.id) }

    @Test func thereAreTwoGroupsInOrder() {
        let rows = build(F.sample())

        #expect(ids(rows) == [.agentSessions, .herder])
        #expect(ids(F.children(of: .herder, in: rows)) == [.process(F.process(F.appPID, parent: 1).key), .terminals])
    }

    @Test func anAgentSessionHoldsItsWholeTree() throws {
        // agent (200) -> build (300) -> compiler (400): a grandchild.
        let agent = F.owner(.agentSession, "Syntax highlighting", pid: 200, state: .working)
        let sample = F.sample(
            F.process(200, "opencode"), F.process(300, parent: 200, "make"), F.process(400, parent: 300, "cc")
        )

        let rows = build(sample, owners: [agent])

        let session = try #require(F.children(of: .agentSessions, in: rows).first)
        #expect(session.id == .tab(agent.id))
        #expect(session.name == "Syntax highlighting")
        #expect(session.status == .working)
        #expect(session.processCount == 3)
        let tui = try #require(session.children.first)
        #expect(tui.name == "opencode")
        #expect(tui.children.first?.children.first?.name == "cc")
    }

    @Test func aSessionNamesItsWorktreeAndBranch() throws {
        let agent = F.owner(.agentSession, "Fix", pid: 200, worktree: "/code/api", branch: "feat/x")

        let rows = build(F.sample(F.process(200)), owners: [agent])

        let session = try #require(F.children(of: .agentSessions, in: rows).first)
        #expect(session.subtitle == "api \u{00B7} feat/x")
        #expect(session.searchTerms.contains("api"))
        #expect(session.searchTerms.contains("200"))
    }

    @Test func aSessionTakesItsStatusFromWhatTheSidebarReads() {
        let states: [(AgentSession.State, TaskRow.Status)] = [
            (.working, .working), (.needsInput("ok?"), .needsYou), (.idle, .idle),
            (.starting, .starting), (.failed, .failed), (.exited(1), .done),
        ]
        for (state, status) in states {
            let agent = F.owner(.agentSession, "A", pid: 200, state: state)
            let row = build(F.sample(F.process(200)), owners: [agent])
            #expect(F.children(of: .agentSessions, in: row).first?.status == status)
        }
    }

    @Test func anAgentThatExitedIsDoneWithZerosAndNoChildren() throws {
        let agent = F.owner(.agentSession, "Done one", pid: nil, state: .exited(1))
        // A process may even still be there under its old pid.
        let rows = build(F.sample(F.process(200)), owners: [agent])

        let session = try #require(F.children(of: .agentSessions, in: rows).first)
        #expect(session.status == .done)
        #expect(session.children.isEmpty)
        #expect(session.cpu == 0)
        #expect(session.memory == 0)
        #expect(session.threads == 0)
        #expect(session.processCount == 0)
    }

    @Test func aRestoredTabIsListedPausedWithZeros() throws {
        let agent = F.owner(.agentSession, "Waiting", pid: nil, state: .paused)

        let rows = build(F.sample(), owners: [agent])

        let session = try #require(F.children(of: .agentSessions, in: rows).first)
        #expect(session.status == .paused)
        #expect(session.children.isEmpty)
        #expect(session.cpu == 0)
        #expect(session.processCount == 0)
    }

    @Test func terminalsAreUnderTheirOwnGroupInsideHerder() throws {
        let shell = F.owner(.terminal, "zsh", pid: 200)
        let rows = build(F.sample(F.process(200, "zsh"), F.process(300, parent: 200, "vim")), owners: [shell])

        let terminal = try #require(F.children(of: .terminals, in: rows).first)
        #expect(terminal.kind == .terminal)
        #expect(terminal.processCount == 2)
        #expect(F.children(of: .agentSessions, in: rows).isEmpty)
    }

    @Test func childrenNoTabClaimsAreOther() throws {
        let agent = F.owner(.agentSession, "A", pid: 200)
        let rows = build(
            F.sample(F.process(200), F.process(500, "git"), F.process(501, parent: 500, "git-remote")),
            owners: [agent]
        )

        let other = F.children(of: .other, in: rows)
        #expect(other.map(\.name) == ["git"])
        #expect(other.first?.children.map(\.name) == ["git-remote"])
    }

    @Test func otherIsLeftOutWhenEveryChildIsClaimed() {
        let agent = F.owner(.agentSession, "A", pid: 200)
        let rows = build(F.sample(F.process(200)), owners: [agent])

        #expect(!ids(F.children(of: .herder, in: rows)).contains(.other))
    }

    @Test func herderRowIsTheAppAloneWithItsOwnNumbers() throws {
        let rows = build(F.sample(F.process(200)), cpu: [F.process(F.appPID, parent: 1).key: 12.5])

        let app = try #require(F.children(of: .herder, in: rows).first)
        #expect(app.kind == .herder)
        #expect(app.name == "Herder")
        #expect(app.processCount == 1)
        #expect(app.cpu == 12.5)
        #expect(app.children.isEmpty)
    }

    @Test func rowsRollTheirSubtreeUp() throws {
        let agent = F.owner(.agentSession, "A", pid: 200)
        let sample = F.sample(
            F.process(200, mb: 100, threads: 4), F.process(300, parent: 200, mb: 50, threads: 3)
        )
        let cpu = [F.process(200).key: 10.0, F.process(300).key: 5.0]

        let rows = build(sample, cpu: cpu, owners: [agent])

        let session = try #require(F.children(of: .agentSessions, in: rows).first)
        #expect(session.cpu == 15)
        #expect(session.memory == 150 << 20)
        #expect(session.threads == 7)
        let group = try #require(rows.first)
        #expect(group.cpu == 15)
        #expect(group.processCount == 2)
    }

    @Test func aRowWithNoRatesAnywhereShowsNone() throws {
        let agent = F.owner(.agentSession, "A", pid: 200)
        let rows = build(F.sample(F.process(200)), owners: [agent])

        #expect(try #require(F.children(of: .agentSessions, in: rows).first).cpu == nil)
    }

    @Test func aProcessIsRunningOnlyWhileOnACPU() {
        let rows = build(F.sample(F.process(200, running: true), F.process(201, running: false)))

        let other = F.children(of: .other, in: rows)
        #expect(other.map(\.status) == [.running, .sleeping])
    }

    @Test func aTabWhoseProcessHasGoneFromTheSampleHasNoChildren() throws {
        let shell = F.owner(.terminal, "zsh", pid: 999)
        let rows = build(F.sample(), owners: [shell])

        let terminal = try #require(F.children(of: .terminals, in: rows).first)
        #expect(terminal.children.isEmpty)
        #expect(terminal.processCount == 0)
    }

    @Test func aReusedPidGetsItsOwnRowKey() {
        let old = F.process(200, started: 1)
        let new = F.process(200, started: 2)

        #expect(TaskRow.ID.process(old.key) != TaskRow.ID.process(new.key))
    }

    @Test func aLoopInTheParentsDoesNotRepeatAProcess() {
        // 300's parent is 301 and 301's is 300: neither reaches the app.
        let rows = build(F.sample(F.process(200), F.process(300, parent: 301), F.process(301, parent: 300)))

        #expect(rows.first(where: { $0.id == .herder })?.processCount == 2)
    }
}
