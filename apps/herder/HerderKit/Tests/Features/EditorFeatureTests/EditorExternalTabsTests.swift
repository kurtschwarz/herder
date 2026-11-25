import Core
import Foundation
import TestSupport
import Testing

@testable import EditorFeature

/// A file outside every workspace, such as `settings.json`, in a tab of its
/// own: the window's, not the workspace's.
@Suite @MainActor struct EditorExternalTabsTests {
    let files = InMemoryFileClient()
    let watcher = StubFileWatcherClient()
    let store: WorkspaceRegistry
    let model: EditorModel
    let root = URL(filePath: "/code/api")
    let other = URL(filePath: "/code/web")
    let home = URL(filePath: "/Users/test", directoryHint: .isDirectory)
    let settings = URL(filePath: "/Users/test/.config/herder/settings.json")
    let window = NSObject()

    init() {
        store = WorkspaceRegistry(
            files: files,
            git: StubGitClient(),
            watcher: watcher,
            clock: VirtualClockClient(),
            state: InMemoryStateStore()
        )
        model = EditorModel(store: store, files: files, highlighter: NoSyntaxHighlighter(), watcher: watcher, home: home)
        files.seed(settings.path(percentEncoded: false), "{}\n")
    }

    var settingsKey: PathKey { PathKey(settings) }
    var folder: URL { settings.deletingLastPathComponent() }

    func open(_ workspace: URL, with names: [String]) async throws -> Workspace {
        for name in names { files.seed(workspace.appending(path: name).path(percentEncoded: false), name) }
        files.seed(
            children: names.map { DirectoryEntry(url: workspace.appending(path: $0), isDirectory: false) },
            of: workspace
        )
        store.display(WorkspaceID(workspace), from: window)
        let state = try #require(await store.open(WorkspaceID(workspace)))
        await state.refresh()
        return state
    }

    func settle() async {
        for _ in 0..<500 { await Task.yield() }
    }

    var text: String { model.activeBuffer?.text ?? "" }

    @Test func aFileOutsideTheWorkspaceOpensInATabOfItsOwn() async throws {
        let api = try await open(root, with: ["a.txt"])
        await model.restore(in: api)

        await model.openExternal(settings)

        #expect(model.tabs.last == settingsKey)
        #expect(model.activeTab == settingsKey)
        #expect(model.isShowingExternal)
        #expect(text == "{}\n")
    }

    @Test func itWorksWithNoWorkspaceAtAll() async {
        await model.restore(in: nil)

        await model.openExternal(settings)

        #expect(model.tabs == [settingsKey])
        #expect(text == "{}\n")
        #expect(model.canCreateFile == false)
    }

    @Test func openingItFocusedAsksForTheKeyboard() async throws {
        await model.openExternal(settings, focusing: true)

        // No window in a test, so the pane takes it once it has one.
        #expect(try #require(model.activeBuffer).wantsFocus)
    }

    @Test func aRequestToFocusOutlivesTheRestore() async throws {
        model.requestOpenExternal(settings, focusing: true)

        await model.restore(in: nil)

        #expect(try #require(model.activeBuffer).wantsFocus)
    }

    @Test func itsBreadcrumbStartsAtHome() async {
        await model.openExternal(settings)

        #expect(model.breadcrumb == ["~", ".config", "herder", "settings.json"])
    }

    @Test func itStaysThroughAWorkspaceSwitch() async throws {
        let api = try await open(root, with: ["a.txt"])
        let web = try await open(other, with: ["b.txt"])
        await model.restore(in: api)
        await model.open(root.appending(path: "a.txt"))
        await model.openExternal(settings)

        await model.restore(in: web)

        #expect(model.tabs.contains(settingsKey))
        await model.activate(settingsKey)
        #expect(model.activeTab == settingsKey)
        #expect(text == "{}\n")

        await model.restore(in: api)
        #expect(model.tabs == [PathKey(root.appending(path: "a.txt")), settingsKey])
        #expect(model.activeTab == PathKey(root.appending(path: "a.txt")))
    }

    @Test func itShowsWhenTheWorkspaceHasNothingTo() async throws {
        let web = try await open(other, with: ["b.txt"])
        await model.openExternal(settings)

        await model.restore(in: web)

        #expect(model.activeTab == settingsKey)
    }

    @Test func itIsNotRemembered() async throws {
        let api = try await open(root, with: ["a.txt"])
        await model.restore(in: api)
        await model.open(root.appending(path: "a.txt"))

        await model.openExternal(settings)

        let ui = api.uiState(EditorUIState.self)
        #expect(ui.files == [PathKey(root.appending(path: "a.txt"))])
        #expect(ui.active == PathKey(root.appending(path: "a.txt")))
    }

    @Test func aRequestBeforeTheRestoreIsAnsweredByIt() async throws {
        let api = try await open(root, with: ["a.txt"])
        model.requestOpenExternal(settings)

        await model.restore(in: api)

        #expect(model.activeTab == settingsKey)
    }

    @Test func anOutsideWriteReloadsACleanBuffer() async {
        await model.openExternal(settings)

        files.seed(settings.path(percentEncoded: false), #"{"x":1}"#)
        watcher.change([folder])
        await settle()

        #expect(text == #"{"x":1}"#)
        #expect(model.isStale == false)
    }

    @Test func anOutsideWriteUnderEditsLeavesThemAndSaysItIsStale() async throws {
        await model.openExternal(settings)
        let buffer = try #require(model.activeBuffer)
        buffer.storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "// mine\n")
        model.bufferDidChange(buffer)

        files.seed(settings.path(percentEncoded: false), #"{"x":1}"#)
        watcher.change([folder])
        await settle()

        #expect(text == "// mine\n{}\n")
        #expect(model.isStale)
    }

    @Test func aDeletedFileShowsAsDeleted() async {
        await model.openExternal(settings)

        files.removeFile(settings.path(percentEncoded: false))
        watcher.change([folder])
        await settle()

        #expect(model.isDeleted)
        #expect(text == "{}\n")
    }

    @Test func savingWritesItWhereItIs() async throws {
        await model.openExternal(settings)
        let buffer = try #require(model.activeBuffer)
        buffer.storage.replaceCharacters(in: NSRange(location: 1, length: 0), with: #""a":1"#)
        model.bufferDidChange(buffer)

        await model.save()

        #expect(files.writes == [.init(path: settingsKey.path, contents: #"{"a":1}"# + "\n")])
    }

    @Test func itCannotBePinnedAndClosingItStopsTheWatch() async {
        await model.openExternal(settings)

        model.togglePin(settingsKey)
        #expect(model.openTabs.first?.isPinned == false)

        await model.close(tab: settingsKey)
        #expect(model.tabs.isEmpty)
        #expect(model.activeTab == nil)
    }

    @Test func aDiagnosticShowsOverItsTab() async {
        model.diagnostic = { [settingsKey] key in key == settingsKey ? "agents.custom[0].id is missing." : nil }

        await model.openExternal(settings)

        #expect(model.activeDiagnostic == "agents.custom[0].id is missing.")
    }
}
