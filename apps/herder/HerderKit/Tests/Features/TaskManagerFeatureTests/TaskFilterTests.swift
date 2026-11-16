import Foundation
import Testing

import Core

@testable import TaskManagerFeature

/// The All / Agents / Herder control and the filter field.
@Suite struct TaskFilterTests {
    typealias F = ProcessFixtures

    /// Two agent sessions, a terminal, and one process nobody claimed.
    func rows() -> [TaskRow] {
        let api = F.owner(.agentSession, "Syntax highlighting", pid: 200, worktree: "/code/api", branch: "main")
        let web = F.owner(.agentSession, "Fix scroll jank", pid: 210, worktree: "/code/web", branch: "scroll")
        let shell = F.owner(.terminal, "zsh", pid: 220)
        let sample = F.sample(
            F.process(200, "opencode"), F.process(201, parent: 200, "cargo"),
            F.process(210, "claude"), F.process(220, "zsh"), F.process(500, "git")
        )
        return TaskTree.build(sample: sample, cpu: [:], owners: [api, web, shell])
    }

    func names(_ rows: [TaskRow]) -> [String] {
        rows.flatMap { [$0.name] + names($0.children) }
    }

    @Test func allShowsEverything() {
        #expect(TaskFilter.apply(rows(), scope: .all, text: "").map(\.id) == [.agentSessions, .herder])
    }

    @Test func agentsShowsOnlyTheSessions() {
        #expect(TaskFilter.apply(rows(), scope: .agents, text: "").map(\.id) == [.agentSessions])
    }

    @Test func herderShowsOnlyHerder() {
        #expect(TaskFilter.apply(rows(), scope: .herder, text: "").map(\.id) == [.herder])
    }

    @Test func textMatchesANameWithoutRegardToCase() {
        let found = names(TaskFilter.apply(rows(), scope: .all, text: "SCROLL"))

        #expect(found.contains("Fix scroll jank"))
        #expect(!found.contains("Syntax highlighting"))
    }

    @Test func textMatchesAWorktree() {
        let found = names(TaskFilter.apply(rows(), scope: .all, text: "web"))

        #expect(found.contains("Fix scroll jank"))
        #expect(!found.contains("Syntax highlighting"))
    }

    @Test func textMatchesABranch() {
        #expect(names(TaskFilter.apply(rows(), scope: .all, text: "scroll")).contains("Fix scroll jank"))
    }

    @Test func textMatchesAPid() {
        let found = names(TaskFilter.apply(rows(), scope: .all, text: "500"))

        #expect(found.contains("git"))
        #expect(!found.contains("zsh"))
    }

    @Test func anAncestorOfAMatchStays() {
        // "cargo" is under the session and its opencode process.
        let found = TaskFilter.apply(rows(), scope: .all, text: "cargo")

        #expect(names(found).contains("Agent Sessions"))
        #expect(names(found).contains("Syntax highlighting"))
        #expect(names(found).contains("opencode"))
        #expect(names(found).contains("cargo"))
        #expect(!names(found).contains("claude"))
    }

    @Test func aMatchKeepsWhatIsUnderIt() {
        let found = names(TaskFilter.apply(rows(), scope: .all, text: "Syntax"))

        #expect(found.contains("opencode"))
        #expect(found.contains("cargo"))
    }

    @Test func aGroupGoesWhenNothingUnderItMatches() {
        let found = TaskFilter.apply(rows(), scope: .all, text: "cargo")

        #expect(found.map(\.id) == [.agentSessions])
    }

    @Test func aGroupsOwnNameIsNotAMatch() {
        #expect(TaskFilter.apply(rows(), scope: .all, text: "Terminals").isEmpty)
    }

    @Test func blankTextMatchesEverything() {
        let all = rows()

        #expect(TaskFilter.apply(all, scope: .all, text: "   ") == all)
    }

    @Test func scopeAndTextWorkTogether() {
        // "zsh" is a Herder row; limited to agents, nothing is left.
        #expect(TaskFilter.apply(rows(), scope: .agents, text: "zsh").isEmpty)
    }
}
