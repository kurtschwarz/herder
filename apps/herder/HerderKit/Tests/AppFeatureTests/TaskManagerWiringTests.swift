import Core
import Foundation
import Services
import TaskManagerFeature
import TestSupport
import Testing

@testable import AppFeature

/// The Task Manager as the composition root joins it up: one registry for every
/// window's panels, read by a model of its own, and a way back to the tab.
@Suite(.timeLimit(.minutes(1))) @MainActor struct TaskManagerWiringTests {
    let files = InMemoryFileClient()
    let pty = StubPTYClient()
    let monitor = StubProcessMonitorClient()
    let environment: AppEnvironment

    private let api = URL(filePath: "/code/api")
    private let web = URL(filePath: "/code/web")

    init() {
        environment = AppEnvironment(
            files: files,
            bookmarks: InMemoryBookmarkClient(),
            git: StubGitClient(),
            folderPicker: StubFolderPickerClient(),
            watcher: StubFileWatcherClient(),
            clock: VirtualClockClient(),
            persistence: PersistenceStack.temporary(),
            pty: pty,
            processMonitor: monitor
        )
        for folder in [api, web] {
            files.seed(folder.appending(path: "a.txt").path(percentEncoded: false), "a")
            files.seed(
                children: [DirectoryEntry(url: folder.appending(path: "a.txt"), isDirectory: false)],
                of: folder
            )
        }
    }

    /// A window showing `folder`, with a shell open in it.
    private func window(showing folder: URL) async -> WindowEnvironment {
        let window = environment.makeWindow()
        window.activate(WorkspaceID(folder))
        await window.showActiveWorkspace()
        await window.terminal.openTab()
        return window
    }

    @Test func everyWindowsShellsAreInTheOneRegistry() async {
        let first = await window(showing: api)
        let second = await window(showing: web)

        #expect(environment.processes.entries.count == 2)
        #expect(Set(environment.processes.entries.map(\.window)) == [first.id, second.id])
        #expect(Set(environment.processes.entries.map(\.workspace)) == [WorkspaceID(api), WorkspaceID(web)])
    }

    @Test func theTaskManagerSeesTheSessionsOfEveryWindow() async throws {
        _ = await window(showing: api)
        _ = await window(showing: web)
        monitor.enqueue(ProcessSample(
            root: 1, takenAt: Date(), coreCount: 8, physicalMemory: 16 << 30,
            processes: [SampledProcess(pid: 1, parent: 0, name: "Herder")]
                + pty.sessions.map { SampledProcess(pid: $0.pid, parent: 1, name: "zsh", started: UInt64($0.pid)) }
        ))
        let model = environment.makeTaskManager()

        await model.refresh()

        let terminals = model.rows.first { $0.id == .herder }?.children.first { $0.id == .terminals }?.children
        #expect(terminals?.count == 2)
    }

    @Test func showingATabFromTheTaskManagerSwitchesItsWindowToIt() async throws {
        let window = await window(showing: api)
        let entry = try #require(environment.processes.entries.first)
        window.activate(WorkspaceID(web))
        await window.showActiveWorkspace()
        window.terminal.hide()

        entry.show()
        #expect(window.activeWorkspaceID == WorkspaceID(api))
        await window.showActiveWorkspace()

        #expect(window.terminal.isOpen)
    }

    @Test func showingASessionFromTheTaskManagerSwitchesItsWindowToIt() async throws {
        let window = environment.makeWindow()
        window.activate(WorkspaceID(api))
        await window.showActiveWorkspace()
        await window.agentPanel.startSession()
        let entry = try #require(environment.processes.entries.first)
        window.activate(WorkspaceID(web))
        await window.showActiveWorkspace()

        entry.show()
        #expect(window.activeWorkspaceID == WorkspaceID(api))
        await window.showActiveWorkspace()

        #expect(window.agentPanel.sessions.focused == entry.id)
    }
}
