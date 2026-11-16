import Core
import Foundation
import TestSupport
import Testing

@testable import TerminalFeature

/// The panel's shells and whether it shows, against a PTY the test plays both
/// ends of.
@Suite(.timeLimit(.minutes(1))) struct TerminalModelTests {
    let files = InMemoryFileClient()
    let git = StubGitClient()
    let watcher = StubFileWatcherClient()
    let clock = VirtualClockClient()
    let state = InMemoryStateStore()
    let pty = StubPTYClient()
    let processes = RunningProcesses()
    let root = URL(filePath: "/code/api")
    let other = URL(filePath: "/code/web")
    let home = URL(filePath: "/Users/kurt")

    func makeRegistry() -> WorkspaceRegistry {
        WorkspaceRegistry(files: files, git: git, watcher: watcher, clock: clock, state: state)
    }

    func makeModel(environment: [String: String] = ["SHELL": "/bin/sh"]) -> TerminalModel {
        TerminalModel(pty: pty, clock: clock, environment: environment, home: home, processes: processes)
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

    /// A model showing `root`, with `count` shells open.
    func shown(tabs count: Int = 0) async throws -> (TerminalModel, Workspace, WorkspaceRegistry) {
        let registry = makeRegistry()
        let model = makeModel()
        let workspace = try await workspace(root, in: registry)
        await model.show(workspace)
        for _ in 0..<count { await model.openTab() }
        return (model, workspace, registry)
    }

    // MARK: Starting a shell

    @Test func aNewTabIsALoginShellInTheWorktreeRoot() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        let spec = try #require(pty.specs.last)
        #expect(spec.executable == "/bin/sh")
        #expect(spec.arguments == ["/bin/sh", "-l"])
        #expect(spec.workingDirectory == root)
        #expect(spec.environment["TERM_PROGRAM"] == "Herder")
        #expect(model.tabs.count == 1)
    }

    @Test func aNewTabStartsInTheRootEvenWhenTheOneBesideItHasMoved() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        pty.sessions[0].changeDirectory(to: URL(filePath: "/code/api/Sources"))
        await model.activeTab?.refresh()

        await model.openTab()
        #expect(pty.specs.last?.workingDirectory == root)
    }

    @Test func aShellThatCannotStartSaysWhyAndOpensNothing() async throws {
        let (model, _, _) = try await shown()
        pty.failSpawns(with: .spawnFailed(ENOENT))
        await model.openTab()
        #expect(model.tabs.isEmpty)
        #expect(model.spawnFailure?.contains("/bin/sh") == true)
        #expect(!model.isOpen)
    }

    @Test func withNoWorkspaceThereIsNothingToStartIn() async throws {
        let model = makeModel()
        await model.show(nil)
        await model.openTab()
        await model.toggle()
        #expect(pty.specs.isEmpty)
        #expect(!model.isOpen)
    }

    // MARK: The panel

    @Test func openingATabOpensThePanel() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        #expect(model.isOpen)
    }

    @Test func togglingOpensOneShellAndAsksForTheKeyboard() async throws {
        let (model, _, _) = try await shown()
        let before = model.focusRequest
        await model.toggle()
        #expect(model.isOpen)
        #expect(model.tabs.count == 1)
        #expect(model.focusRequest > before)
    }

    @Test func hidingKeepsTheShellsAndShowingAgainStartsNoMore() async throws {
        let (model, _, _) = try await shown()
        await model.toggle()
        await model.toggle()
        #expect(!model.isOpen)
        #expect(model.tabs.count == 1)

        await model.toggle()
        #expect(model.isOpen)
        #expect(pty.specs.count == 1)
    }

    @Test func closingTheLastTabHidesThePanel() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        model.closeActiveTab()
        #expect(model.tabs.isEmpty)
        #expect(!model.isOpen)
        #expect(pty.sessions[0].wasTerminated)
    }

    // MARK: Tabs

    @Test func theNewestTabIsTheOneShowing() async throws {
        let (model, _, _) = try await shown(tabs: 3)
        #expect(model.activeTab?.id == model.tabs[2].id)
    }

    @Test func closingTheActiveTabSelectsTheOneThatTookItsPlace() async throws {
        let (model, _, _) = try await shown(tabs: 3)
        let ids = model.tabs.map(\.id)
        model.select(model.tabs[1])
        model.closeActiveTab()
        #expect(model.tabs.map(\.id) == [ids[0], ids[2]])
        #expect(model.activeTab?.id == ids[2])
    }

    @Test func closingTheLastOfSeveralSelectsTheOneBefore() async throws {
        let (model, _, _) = try await shown(tabs: 3)
        let ids = model.tabs.map(\.id)
        model.closeActiveTab()
        #expect(model.activeTab?.id == ids[1])
    }

    @Test func closingATabInTheBackgroundKeepsTheOneShowing() async throws {
        let (model, _, _) = try await shown(tabs: 3)
        let active = model.activeTab?.id
        model.close(model.tabs[0])
        #expect(model.activeTab?.id == active)
        #expect(model.tabs.count == 2)
    }

    @Test func cyclingWrapsAround() async throws {
        let (model, _, _) = try await shown(tabs: 3)
        let ids = model.tabs.map(\.id)
        model.selectNextTab()
        #expect(model.activeTab?.id == ids[0])
        model.selectPreviousTab()
        #expect(model.activeTab?.id == ids[2])
    }

    @Test func cyclingWithOneTabDoesNothing() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        #expect(!model.canSelectOtherTab)
        model.selectNextTab()
        #expect(model.tabs.count == 1)
    }

    // MARK: Pinning a tab

    @Test func aPinnedTabMovesToTheFront() async throws {
        let (model, _, _) = try await shown(tabs: 3)
        let ids = model.tabs.map(\.id)
        model.togglePin(model.tabs[2])
        #expect(model.tabs.map(\.id) == [ids[2], ids[0], ids[1]])
        #expect(model.tabs[0].isPinned)
        #expect(!model.tabs[1].isPinned)
    }

    @Test func pinnedTabsKeepTheOrderTheyWerePinnedIn() async throws {
        let (model, _, _) = try await shown(tabs: 4)
        let ids = model.tabs.map(\.id)
        model.togglePin(model.tabs[3])
        // Now [3, 0, 1, 2]: pin the last of those.
        model.togglePin(model.tabs[3])
        #expect(model.tabs.map(\.id) == [ids[3], ids[2], ids[0], ids[1]])
        #expect(model.tabs.map(\.isPinned) == [true, true, false, false])
    }

    @Test func unpinningSendsItBehindTheRestOfThePinned() async throws {
        let (model, _, _) = try await shown(tabs: 3)
        let ids = model.tabs.map(\.id)
        model.togglePin(model.tabs[0])
        model.togglePin(model.tabs[1])
        model.togglePin(model.tabs[0])
        #expect(model.tabs.map(\.id) == [ids[1], ids[0], ids[2]])
        #expect(model.tabs.map(\.isPinned) == [true, false, false])
    }

    @Test func pinningDoesNotChangeWhichTabIsShowing() async throws {
        let (model, _, _) = try await shown(tabs: 3)
        let active = model.activeTab?.id
        model.togglePin(model.tabs[0])
        #expect(model.activeTab?.id == active)
    }

    @Test func aNewTabOpensAfterThePinnedOnes() async throws {
        let (model, _, _) = try await shown(tabs: 2)
        let pinned = model.tabs[1]
        model.togglePin(pinned)
        await model.openTab()
        #expect(model.tabs.first?.id == pinned.id)
        #expect(model.tabs.last?.isPinned == false)
    }

    @Test func aPinnedTabCanStillBeClosed() async throws {
        let (model, _, _) = try await shown(tabs: 2)
        model.togglePin(model.tabs[0])
        model.close(model.tabs[0])
        #expect(model.tabs.count == 1)
    }

    // MARK: Moving a tab

    @Test func aTabMovesWhereItIsPut() async throws {
        let (model, _, _) = try await shown(tabs: 3)
        let ids = model.tabs.map(\.id)
        let active = model.activeTab?.id

        model.move(model.tabs[0], to: 2)

        #expect(model.tabs.map(\.id) == [ids[1], ids[2], ids[0]])
        #expect(model.activeTab?.id == active)
    }

    @Test func aMoveStaysOnItsSideOfThePinnedTabs() async throws {
        let (model, _, _) = try await shown(tabs: 3)
        model.togglePin(model.tabs[0])
        let ids = model.tabs.map(\.id)

        model.move(model.tabs[2], to: 0)

        #expect(model.tabs.map(\.id) == [ids[0], ids[2], ids[1]])
    }

    // MARK: Naming a tab

    @Test func aNameReplacesWhatIsRunningInTheTitle() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        let tab = try #require(model.activeTab)
        model.rename(tab, to: "server")
        #expect(tab.displayTitle == "server")

        pty.sessions[0].run("swift test")
        await tab.refresh()
        #expect(tab.displayTitle == "server")
        #expect(tab.title == "swift test")
    }

    @Test func aBlankNameGoesBackToFollowingWhatIsRunning() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        let tab = try #require(model.activeTab)
        model.rename(tab, to: "server")
        model.rename(tab, to: "   ")
        #expect(tab.customName == nil)
        #expect(tab.displayTitle == tab.title)
    }

    @Test func aNameIsTrimmedAndHeldToALength() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        let tab = try #require(model.activeTab)
        model.rename(tab, to: "  web  ")
        #expect(tab.customName == "web")
        model.rename(tab, to: String(repeating: "x", count: 200))
        #expect(tab.customName?.count == TerminalTab.maxNameLength)
    }

    @Test func renamingOneTabLeavesTheOthersAlone() async throws {
        let (model, _, _) = try await shown(tabs: 2)
        model.rename(model.tabs[0], to: "api")
        #expect(model.tabs[1].customName == nil)
    }

    @Test func renamingHandsTheKeyboardBackToTheTerminal() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        let before = model.focusRequest
        model.rename(try #require(model.activeTab), to: "x")
        #expect(model.focusRequest > before)
    }

    @Test func aNameDoesNotChangeWhetherTheTabIsBusy() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        let tab = try #require(model.activeTab)
        model.rename(tab, to: "quiet")
        pty.sessions[0].run("sleep 30")
        #expect(await tab.isRunningSomething())
        // The prompt names the command, not the label.
        await model.requestCloseActiveTab()
        #expect(model.closePrompt?.command == "sleep 30")
    }

    // MARK: Closing with something running

    @Test func anIdleShellClosesWithoutAsking() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        await model.requestCloseActiveTab()
        #expect(model.closePrompt == nil)
        #expect(model.tabs.isEmpty)
    }

    @Test func aRunningCommandIsAskedAboutAndTheTabStaysUntilAnswered() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        pty.sessions[0].run("swift build")
        await model.requestCloseActiveTab()
        #expect(model.closePrompt?.command == "swift build")
        #expect(model.tabs.count == 1)
        #expect(!pty.sessions[0].wasTerminated)
    }

    @Test func confirmingEndsTheCommandAndClosesTheTab() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        pty.sessions[0].run("swift build")
        await model.requestCloseActiveTab()
        model.answerClose(confirm: true)
        #expect(model.closePrompt == nil)
        #expect(model.tabs.isEmpty)
        #expect(pty.sessions[0].wasTerminated)
    }

    @Test func decliningLeavesItRunning() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        pty.sessions[0].run("swift build")
        await model.requestCloseActiveTab()
        model.answerClose(confirm: false)
        #expect(model.closePrompt == nil)
        #expect(model.tabs.count == 1)
        #expect(!pty.sessions[0].wasTerminated)
    }

    @Test func aCommandThatFinishedWhileTheQuestionWasUpDoesNotCloseAnythingElse() async throws {
        let (model, _, _) = try await shown(tabs: 2)
        pty.sessions[1].run("sleep 30")
        await model.requestCloseActiveTab()
        model.close(model.tabs[1])
        model.answerClose(confirm: true)
        #expect(model.tabs.count == 1)
        #expect(!pty.sessions[0].wasTerminated)
    }

    @Test func theWindowAndQuitPromptsSeeEveryRunningCommandInEveryWorkspace() async throws {
        let registry = makeRegistry()
        let model = makeModel()
        let api = try await workspace(root, in: registry)
        let web = try await workspace(other, in: registry)
        await model.show(api)
        await model.openTab()
        await model.openTab()
        await model.show(web)
        await model.openTab()

        #expect(model.hasTerminals)
        #expect(await model.runningCommands().isEmpty)

        pty.sessions[1].run("just dev")
        pty.sessions[2].run("tail -f log")
        #expect(Set(await model.runningCommands()) == ["just dev", "tail -f log"])
    }

    @Test func aWindowWithNoTerminalsHasNothingToAskAbout() async throws {
        let (model, _, _) = try await shown()
        #expect(!model.hasTerminals)
        #expect(await model.runningCommands().isEmpty)
    }

    // MARK: When a shell exits

    @Test func aCleanExitTakesItsTabAway() async throws {
        let (model, _, _) = try await shown(tabs: 2)
        let leaving = model.tabs[0]
        pty.sessions[0].exit(with: 0)
        try await eventually("the tab to go") { model.tabs.count == 1 }
        #expect(!model.tabs.contains { $0.id == leaving.id })
        #expect(model.isOpen)
    }

    @Test func aCleanExitOfTheLastShellHidesThePanel() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        pty.sessions[0].exit(with: 0)
        try await eventually("the panel to go") { !model.isOpen }
        #expect(model.tabs.isEmpty)
    }

    @Test func aFailedExitStaysUpWithItsReason() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        let tab = try #require(model.activeTab)
        pty.sessions[0].exit(with: 127)

        try await eventually("the message") { tab.screen.visibleText.contains("[Process exited with code 127]") }
        #expect(model.tabs.count == 1)
        #expect(tab.exitCode == 127)
    }

    @Test func aKeyPressClosesAFailedShell() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        let tab = try #require(model.activeTab)
        pty.sessions[0].exit(with: 1)
        try await eventually("the handler") { tab.screen.onKeyWhileEnded != nil }

        tab.screen.onKeyWhileEnded?()
        #expect(model.tabs.isEmpty)
        #expect(!model.isOpen)
    }

    // MARK: What a tab says

    @Test func aTabIsNamedAfterWhatIsRunning() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        let tab = try #require(model.activeTab)

        await tab.refresh()
        #expect(tab.title == "sh")
        #expect(!tab.isBusy)

        pty.sessions[0].run("swift test --filter EditorStateTests --parallel")
        await tab.refresh()
        #expect(tab.title.hasPrefix("swift test --filter"))
        #expect(tab.title.count <= TerminalTitle.maxLength)
        #expect(tab.isBusy)

        pty.sessions[0].returnToShell()
        await tab.refresh()
        #expect(!tab.isBusy)
    }

    @Test func aTabAsksTheProcessWhetherItIsBusyRatherThanTrustingItsLastLook() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        let tab = try #require(model.activeTab)
        await tab.refresh()
        #expect(!tab.isBusy)

        pty.sessions[0].run("sleep 30")
        #expect(await tab.isRunningSomething())
        #expect(!tab.isBusy)
    }

    @Test func theHeaderFollowsTheShellsDirectory() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        let tab = try #require(model.activeTab)
        pty.sessions[0].changeDirectory(to: URL(filePath: "/Users/kurt/dev"))
        await tab.refresh()
        let directory = try #require(tab.directory)
        #expect(model.label(for: directory) == "~/dev")
    }

    @Test func aDirectoryTheShellReportedBeatsTheOneFound() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        let tab = try #require(model.activeTab)
        pty.sessions[0].emit("\u{1b}]7;file://host/code/api/Tests\u{7}")
        try await eventually("the report") { tab.screen.reportedDirectory != nil }
        await tab.refresh()
        #expect(tab.directory?.path(percentEncoded: false) == "/code/api/Tests")
    }

    // MARK: Workspaces

    @Test func eachWorkspaceHasItsOwnShellsAndSwitchingKeepsThemRunning() async throws {
        let registry = makeRegistry()
        let model = makeModel()
        let api = try await workspace(root, in: registry)
        let web = try await workspace(other, in: registry)

        await model.show(api)
        await model.openTab()
        await model.show(web)
        #expect(model.tabs.isEmpty)
        #expect(!model.isOpen)
        await model.openTab()
        await model.openTab()
        #expect(model.tabs.count == 2)

        await model.show(api)
        #expect(model.tabs.count == 1)
        #expect(model.isOpen)
        #expect(pty.sessions.allSatisfy { !$0.wasTerminated })
        #expect(pty.specs.map(\.workingDirectory) == [root, other, other])
    }

    @Test func discardingAWorkspaceEndsItsShellsOnly() async throws {
        let registry = makeRegistry()
        let model = makeModel()
        let api = try await workspace(root, in: registry)
        let web = try await workspace(other, in: registry)
        await model.show(api)
        await model.openTab()
        await model.show(web)
        await model.openTab()

        model.discard(api.id)
        #expect(pty.sessions[0].wasTerminated)
        #expect(!pty.sessions[1].wasTerminated)
        #expect(model.tabs.count == 1)
    }

    @Test func closingTheWindowEndsEveryShell() async throws {
        let (model, _, _) = try await shown(tabs: 2)
        model.terminateAll()
        #expect(pty.sessions.allSatisfy { $0.wasTerminated })
        #expect(model.tabs.isEmpty)
    }

    // MARK: Height

    @Test func neverDraggedTakesTheDefaultHeight() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        #expect(model.height(in: 900) == TerminalModel.limits.defaultHeight)
    }

    @Test func aDragIsHeldToTheLimitsAndResetGoesBack() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        model.resize(to: 10, in: 900)
        #expect(model.height(in: 900) == TerminalModel.limits.minimumPanel)
        model.resize(to: 5000, in: 900)
        #expect(model.height(in: 900) == 900 - TerminalModel.limits.minimumEditor)

        model.resetHeight()
        #expect(model.height(in: 900) == TerminalModel.limits.defaultHeight)
    }

    // MARK: Across a launch

    @Test func theOpenPanelAndItsHeightComeBackButTheShellIsNew() async throws {
        let first = makeRegistry()
        let model = makeModel()
        let workspace = try await workspace(root, in: first)
        await model.show(workspace)
        await model.openTab()
        model.resize(to: 333, in: 900)
        model.commitHeight()
        await first.close(WorkspaceID(root))

        let second = makeRegistry()
        let relaunched = makeModel()
        let reopened = try await self.workspace(root, in: second)
        await relaunched.show(reopened)

        #expect(relaunched.isOpen)
        #expect(relaunched.height(in: 900) == 333)
        #expect(relaunched.tabs.count == 1)
        #expect(pty.specs.count == 2)
    }

    @Test func aHiddenPanelComesBackHiddenWithNoShell() async throws {
        let first = makeRegistry()
        let model = makeModel()
        let opened = try await workspace(root, in: first)
        await model.show(opened)
        await model.openTab()
        model.hide()
        await first.close(WorkspaceID(root))

        let second = makeRegistry()
        let relaunched = makeModel()
        let reopened = try await workspace(root, in: second)
        await relaunched.show(reopened)
        #expect(!relaunched.isOpen)
        #expect(relaunched.tabs.isEmpty)
        #expect(pty.specs.count == 1)
    }

    // MARK: The Task Manager's list

    @Test func aStartedShellIsListedWithItsProcess() async throws {
        let (model, workspace, _) = try await shown(tabs: 1)

        let tab = try #require(model.activeTab)
        let entry = try #require(processes.entry(tab.id))
        #expect(entry.kind == .terminal)
        #expect(entry.pid == pty.sessions[0].pid)
        #expect(entry.workspace == workspace.id)
        #expect(entry.title() == tab.displayTitle)
        #expect(entry.state() == nil)
    }

    @Test func aShellsEntryGoesWhenItsProcessDoes() async throws {
        let (model, _, _) = try await shown(tabs: 1)
        let id = try #require(model.activeTab?.id)

        pty.sessions[0].exit(with: 1)

        try await eventually("the entry goes") { processes.entry(id) == nil }
        #expect(model.tabs.count == 1)
    }

    @Test func closingATabTakesItsEntryAway() async throws {
        let (model, _, _) = try await shown(tabs: 2)
        let tab = try #require(model.activeTab)

        model.close(tab)

        #expect(processes.entry(tab.id) == nil)
        #expect(processes.entries.count == 1)
    }

    @Test func closingTheWindowOrAWorkspaceTakesTheEntriesAway() async throws {
        let (model, workspace, _) = try await shown(tabs: 2)

        model.discard(workspace.id)
        #expect(processes.entries.isEmpty)

        let (second, _, _) = try await shown(tabs: 1)
        second.terminateAll()
        #expect(processes.entries.isEmpty)
    }

    @Test func showingFromTheTaskManagerAsksTheWindow() async throws {
        let (model, workspace, _) = try await shown(tabs: 1)
        let tab = try #require(model.activeTab)
        nonisolated(unsafe) var asked: (UUID, WorkspaceID)?
        model.onShowTab = { asked = ($0, $1) }

        processes.entry(tab.id)?.show()

        #expect(asked?.0 == tab.id)
        #expect(asked?.1 == workspace.id)
    }

    @Test func revealingBringsATabForwardAndOpensThePanel() async throws {
        let (model, workspace, _) = try await shown(tabs: 2)
        let first = model.tabs[0]
        model.hide()
        #expect(model.activeTab?.id != first.id)

        model.reveal(first.id, in: workspace.id)

        #expect(model.isOpen)
        #expect(model.activeTab?.id == first.id)
    }

    @Test func revealingInAnotherWorkspaceWaitsUntilItIsShowing() async throws {
        let registry = makeRegistry()
        let model = makeModel()
        let api = try await workspace(root, in: registry)
        let web = try await workspace(other, in: registry)
        await model.show(web)
        await model.openTab()
        let tab = try #require(model.activeTab)
        // Web's panel closed, and the window on its way somewhere else.
        model.hide()
        await model.show(api)

        model.reveal(tab.id, in: web.id)
        #expect(!model.isOpen)
        await model.show(web)

        #expect(model.isOpen)
        #expect(model.activeTab?.id == tab.id)
    }

    @Test func revealingATabThatIsNotThereDoesNothing() async throws {
        let (model, workspace, _) = try await shown(tabs: 1)
        model.hide()

        model.reveal(UUID(), in: workspace.id)

        #expect(!model.isOpen)
    }
}

/// Bytes this build did not write: a fixture, because encoding with the current
/// types would move both sides together and prove nothing.
@Suite struct TerminalUIStateTests {
    func decode(_ json: String) throws -> TerminalUIState {
        let state = TerminalUIState()
        try state.restore(from: Data(json.utf8))
        return state
    }

    @Test func readsAnOpenPanelWithAHeight() throws {
        let state = try decode(#"{"isOpen":true,"height":312.5}"#)
        #expect(state.isOpen)
        #expect(state.height == 312.5)
    }

    @Test func aPanelNeverDraggedHasNoHeight() throws {
        let state = try decode(#"{"isOpen":true}"#)
        #expect(state.isOpen)
        #expect(state.height == nil)
    }

    @Test func anEmptyObjectIsAClosedPanel() throws {
        let state = try decode("{}")
        #expect(!state.isOpen)
        #expect(state.height == nil)
    }

    @Test func fieldsAFutureBuildAddsAreIgnored() throws {
        let state = try decode(#"{"isOpen":true,"height":200,"splits":[1,2]}"#)
        #expect(state.isOpen)
        #expect(state.height == 200)
    }

    @Test func thePersistenceKeyIsTheOneOnDisk() {
        #expect(TerminalUIState.persistenceKey == "terminal.panel")
    }

    @Test func whatIsWrittenIsWhatIsRead() throws {
        let state = TerminalUIState()
        state.isOpen = true
        state.height = 280
        let copy = TerminalUIState()
        try copy.restore(from: try state.encode())
        #expect(copy.isOpen)
        #expect(copy.height == 280)
    }
}
