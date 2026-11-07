import Core
import Foundation
import TestSupport
import Testing

@testable import AgentSessionsFeature

/// The panel's sessions and whether it shows, against a PTY the test plays
/// both ends of.
@Suite(.timeLimit(.minutes(1))) struct AgentPanelModelTests {
    let files = InMemoryFileClient()
    let git = StubGitClient()
    let watcher = StubFileWatcherClient()
    let clock = VirtualClockClient()
    let state = InMemoryStateStore()
    let pty = StubPTYClient()
    let root = URL(filePath: "/code/api")
    let other = URL(filePath: "/code/web")

    func makeRegistry() -> WorkspaceRegistry {
        WorkspaceRegistry(files: files, git: git, watcher: watcher, clock: clock, state: state)
    }

    func makeModel() -> AgentPanelModel {
        AgentPanelModel(pty: pty, environment: ["SHELL": "/bin/sh"])
    }

    func workspace(_ url: URL, in registry: WorkspaceRegistry) async throws -> Workspace {
        try #require(await registry.open(WorkspaceID(url)))
    }

    func eventually(_ what: String, _ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("never happened: \(what)")
    }

    /// A model showing `root`, with `count` sessions started.
    func shown(sessions count: Int = 0) async throws -> (AgentPanelModel, Workspace, WorkspaceRegistry) {
        let registry = makeRegistry()
        let model = makeModel()
        let workspace = try await workspace(root, in: registry)
        await model.show(workspace)
        for _ in 0..<count { await model.startSession() }
        return (model, workspace, registry)
    }

    // MARK: Starting

    @Test func aSessionIsOpencodeOnItsOwnServerInTheWorktreeRoot() async throws {
        let (model, _, _) = try await shown(sessions: 1)

        let spec = try #require(pty.specs.last)
        #expect(spec.executable == "/bin/sh")
        #expect(spec.arguments == ["/bin/sh", "-l", "-i", "-c", "exec opencode --standalone"])
        #expect(spec.workingDirectory == root)
        #expect(model.isOpen)
        #expect(model.activeTab?.phase == .running)
    }

    @Test func eachSessionIsAFreshProcessAndTheNewestComesForward() async throws {
        let (model, _, _) = try await shown(sessions: 2)

        #expect(pty.specs.count == 2)
        #expect(model.tabs.map { model.title(of: $0) } == ["Session 1", "Session 2"])
        #expect(model.activeTab?.number == 2)
    }

    @Test func aProcessThatCannotStartSaysWhy() async throws {
        let (model, _, _) = try await shown()
        pty.failSpawns(with: .spawnFailed(ENOENT))

        await model.startSession()

        guard case .failed(let reason)? = model.activeTab?.phase else {
            Issue.record("expected a failure, got \(String(describing: model.activeTab?.phase))")
            return
        }
        #expect(reason.contains("/bin/sh"))
    }

    // MARK: Closing

    @Test func closingATabEndsItsProcessAndLeavesThePanelUp() async throws {
        let (model, _, _) = try await shown(sessions: 1)

        model.close(try #require(model.activeTab))

        #expect(pty.sessions[0].wasTerminated)
        #expect(model.tabs.isEmpty)
        #expect(model.isOpen)
    }

    @Test func closingTheTabShowingBringsItsNeighbourForward() async throws {
        let (model, _, _) = try await shown(sessions: 3)
        model.select(model.tabs[1])

        model.closeActiveTab()

        #expect(model.activeTab?.number == 3)
    }

    @Test func quittingTheTerminalUIClosesItsTab() async throws {
        let (model, _, _) = try await shown(sessions: 1)

        pty.sessions[0].exit(with: 0)

        try await eventually("the tab goes") { model.tabs.isEmpty }
    }

    @Test func aCrashKeepsTheTabAndAReattachStartsItAgain() async throws {
        let (model, _, _) = try await shown(sessions: 1)

        pty.sessions[0].exit(with: 1)
        try await eventually("the tab notices") { model.activeTab?.phase == .exited(1) }
        #expect(model.tabs.count == 1)

        await model.reattach(try #require(model.activeTab))

        #expect(pty.specs.count == 2)
        #expect(model.activeTab?.phase == .running)
    }

    // MARK: Workspaces

    @Test func switchingAwayAndBackKeepsTheProcessRunning() async throws {
        let (model, first, registry) = try await shown(sessions: 1)

        await model.show(try await workspace(other, in: registry))
        #expect(model.tabs.isEmpty)
        await model.show(first)

        #expect(model.tabs.count == 1)
        #expect(pty.specs.count == 1)
        #expect(!pty.sessions[0].wasTerminated)
    }

    @Test func aSessionAskedForInAnotherWorkspaceStartsWhenItIsShown() async throws {
        let (model, _, registry) = try await shown()
        let web = try await workspace(other, in: registry)

        model.requestSession(in: web.id)
        #expect(pty.specs.isEmpty)
        await model.show(web)

        #expect(model.tabs.count == 1)
        #expect(model.isOpen)
        #expect(pty.specs.last?.workingDirectory == other)
    }

    @Test func aRequestForAWorkspaceThatNeverCameStartsNothingInAnotherOne() async throws {
        let (model, first, _) = try await shown()

        model.requestSession(in: WorkspaceID(other))
        await model.show(first)
        await model.show(first)

        #expect(model.tabs.isEmpty)
    }

    @Test func discardingAWorkspaceEndsItsProcesses() async throws {
        let (model, workspace, _) = try await shown(sessions: 1)

        model.discard(workspace.id)

        #expect(pty.sessions[0].wasTerminated)
        #expect(model.tabs.isEmpty)
    }

    // MARK: Remembering

    @Test func anOpenPanelComesBackWithOneFreshSession() async throws {
        let registry = makeRegistry()
        let first = makeModel()
        let workspace = try await workspace(root, in: registry)
        await first.show(workspace)
        await first.startSession()
        await first.startSession()
        await workspace.saveSnapshot()

        // A relaunch: the same state on disk, a new workspace and a new model.
        let model = makeModel()
        let before = pty.specs.count
        await model.show(try await self.workspace(root, in: makeRegistry()))

        #expect(model.isOpen)
        #expect(model.tabs.count == 1)
        #expect(pty.specs.count == before + 1)
    }

    @Test func aHiddenPanelStartsNothingWhenItsWorkspaceIsShown() async throws {
        let registry = makeRegistry()
        let first = makeModel()
        let workspace = try await workspace(root, in: registry)
        await first.show(workspace)
        await first.startSession()
        first.hide()
        await workspace.saveSnapshot()

        let model = makeModel()
        let before = pty.specs.count
        await model.show(try await self.workspace(root, in: makeRegistry()))

        #expect(!model.isOpen)
        #expect(pty.specs.count == before)
    }

    // MARK: Toggling and cycling

    @Test func openingAnEmptyPanelStartsASession() async throws {
        let (model, _, _) = try await shown()

        await model.toggle()

        #expect(model.isOpen)
        #expect(model.tabs.count == 1)
    }

    @Test func hidingKeepsTheSessionsAndShowingDoesNotStartAnother() async throws {
        let (model, _, _) = try await shown(sessions: 1)

        model.hide()
        await model.toggle()

        #expect(model.tabs.count == 1)
        #expect(pty.specs.count == 1)
    }

    @Test func tabsCycleInBothDirections() async throws {
        let (model, _, _) = try await shown(sessions: 2)
        #expect(model.canSelectOtherTab)

        model.selectNextTab()
        #expect(model.activeTab?.number == 1)
        model.selectPreviousTab()
        #expect(model.activeTab?.number == 2)
    }
}
