import Core
import Foundation
import TestSupport
import Testing

@testable import EditorFeature

@Suite @MainActor struct EditorUntitledTests {
    let files = InMemoryFileClient()
    let watcher = StubFileWatcherClient()
    let picker = StubSaveLocationClient()
    let store: WorkspaceRegistry
    let model: EditorModel
    let root = URL(filePath: "/code/api")
    let window = NSObject()

    init() {
        store = WorkspaceRegistry(
            files: files,
            git: StubGitClient(),
            watcher: watcher,
            clock: VirtualClockClient(),
            state: InMemoryStateStore()
        )
        model = EditorModel(store: store, files: files, highlighter: NoSyntaxHighlighter(), saveLocation: picker)
    }

    func path(_ name: String) -> String { root.appending(path: name).path(percentEncoded: false) }
    func url(_ name: String) -> URL { root.appending(path: name) }
    func key(_ name: String) -> PathKey { PathKey(canonical: path(name)) }

    func start(with texts: [String: String] = [:]) async throws -> Workspace {
        for (name, text) in texts { files.seed(path(name), text) }
        files.seed(
            children: texts.keys.sorted().map { DirectoryEntry(url: url($0), isDirectory: false) },
            of: root
        )
        store.display(WorkspaceID(root), from: window)
        let state = try #require(await store.open(WorkspaceID(root)))
        await state.refresh()
        await model.restore(in: state)
        return state
    }

    func type(_ text: String) throws {
        let buffer = try #require(model.activeBuffer)
        buffer.storage.replaceCharacters(in: NSRange(location: buffer.storage.length, length: 0), with: text)
        model.bufferDidChange(buffer)
    }

    var names: [String] { model.openTabs.map(\.name) }

    // MARK: - Creating

    @Test func aNewTabIsShownAtTheEndOfTheStrip() async throws {
        _ = try await start(with: ["a.txt": "one", "b.txt": "two"])
        await model.open(url("a.txt"))
        await model.open(url("b.txt"))

        await model.newUntitled()

        #expect(names == ["a.txt", "b.txt", "Untitled"])
        #expect(model.activeTab?.isUntitled == true)
        #expect(model.file == nil)
        #expect(model.activeBuffer != nil)
    }

    @Test func nothingIsCreatedWithoutAWorkspace() async {
        #expect(model.canCreateFile == false)

        await model.newUntitled()

        #expect(model.tabs.isEmpty)
    }

    @Test func tabsAreNumberedAndANumberIsReusedOnceItsTabCloses() async throws {
        _ = try await start()
        await model.newUntitled()
        await model.newUntitled()
        await model.newUntitled()
        #expect(names == ["Untitled", "Untitled 2", "Untitled 3"])

        await model.close(tab: model.tabs[1])
        await model.newUntitled()

        #expect(names == ["Untitled", "Untitled 3", "Untitled 2"])
    }

    @Test func itIsPlainTextWithABreadcrumbAndNoFolderToTellItApart() async throws {
        _ = try await start(with: ["Untitled": "a real file"])
        await model.open(url("Untitled"))

        await model.newUntitled()

        #expect(model.language == nil)
        #expect(model.breadcrumb == ["api", "Untitled"])
        #expect(model.openTabs.last?.folder == nil)
    }

    @Test func itCanBePinnedAndMoved() async throws {
        _ = try await start(with: ["a.txt": "one"])
        await model.open(url("a.txt"))
        await model.newUntitled()
        let untitled = try #require(model.activeTab)

        model.move(untitled, to: 0)
        #expect(names == ["Untitled", "a.txt"])

        model.togglePin(untitled)
        #expect(model.pinned.contains(untitled))
    }

    // MARK: - Dirty

    @Test func anEmptyTabIsNeverDirtyAndClosesWithoutAsking() async throws {
        _ = try await start()
        await model.newUntitled()

        #expect(model.unsavedFiles.isEmpty)
        await model.requestClose(tab: model.tabs[0])

        #expect(model.closePrompt == nil)
        #expect(model.tabs.isEmpty)
    }

    @Test func aTabWithTextAsksBeforeClosing() async throws {
        _ = try await start()
        await model.newUntitled()
        try type("hello")

        #expect(model.unsavedFiles == ["Untitled"])
        await model.requestClose(tab: model.tabs[0])

        #expect(model.closePrompt?.name == "Untitled")
        #expect(model.tabs.count == 1)
    }

    // MARK: - Switching workspaces

    @Test func aTabWithTextComesBackAndAnEmptyOneIsDropped() async throws {
        let state = try await start()
        await model.newUntitled()
        try type("kept")
        await model.newUntitled()

        await model.restore(in: nil)
        await model.restore(in: state)

        #expect(names == ["Untitled"])
        #expect(model.activeBuffer?.text == "kept")
    }

    // MARK: - Saving

    @Test func theFirstSaveAsksStartingAtTheFolderOfTheLastRealFile() async throws {
        files.seed(path("src/a.txt"), "one")
        _ = try await start()
        await model.open(url("src/a.txt"))
        await model.newUntitled()
        try type("hello")

        await model.save()

        #expect(picker.requests == [.init(suggestedName: "Untitled", directory: url("src"))])
    }

    @Test func withNoRealFileTheSavePanelStartsAtTheWorktreeRoot() async throws {
        _ = try await start()
        await model.newUntitled()
        try type("hello")

        await model.save()

        #expect(picker.requests.map(\.directory) == [root])
    }

    @Test func savingTurnsTheTabIntoAFileTabInPlace() async throws {
        _ = try await start(with: ["a.txt": "one", "z.txt": "zed"])
        await model.open(url("z.txt"))
        await model.open(url("a.txt"))
        await model.newUntitled()
        await model.activate(key("a.txt"))
        await model.activate(model.tabs[2])
        try type("let x = 1")
        let buffer = try #require(model.activeBuffer)
        picker.script(url("new.swift"))

        await model.save()

        #expect(names == ["z.txt", "a.txt", "new.swift"])
        #expect(model.activeTab == key("new.swift"))
        #expect(model.file == url("new.swift"))
        #expect(model.activeBuffer === buffer)
        #expect(model.isDirty(key("new.swift")) == false)
        #expect(try await files.read(path("new.swift"), maxBytes: 100) == "let x = 1")
        #expect(model.unsavedFiles.isEmpty)
    }

    @Test func cancellingTheSavePanelLeavesTheTabUntitledWithoutAnAlert() async throws {
        _ = try await start()
        await model.newUntitled()
        try type("hello")
        picker.script(nil)

        await model.save()

        #expect(names == ["Untitled"])
        #expect(model.saveFailure == nil)
        #expect(model.isDirty(model.tabs[0]))
    }

    @Test func savingOutsideTheWorkspaceIsRefused() async throws {
        _ = try await start()
        await model.newUntitled()
        try type("hello")
        picker.script(URL(filePath: "/elsewhere/out.txt"))

        await model.save()

        #expect(names == ["Untitled"])
        #expect(model.saveFailure?.name == "Untitled")
        #expect(await files.exists("/elsewhere/out.txt") == false)
    }

    @Test func savingOntoAnOpenFileMergesTheTwoTabs() async throws {
        _ = try await start(with: ["a.txt": "one"])
        await model.open(url("a.txt"))
        await model.newUntitled()
        try type("replacement")
        picker.script(url("a.txt"))

        await model.save()

        #expect(names == ["a.txt"])
        #expect(model.activeTab == key("a.txt"))
        #expect(model.activeBuffer?.text == "replacement")
        #expect(model.unsavedFiles.isEmpty)
    }

    @Test func theCloseQuestionsSaveClosesTheNewFilesTab() async throws {
        _ = try await start()
        await model.newUntitled()
        try type("hello")
        picker.script(url("hello.txt"))

        await model.requestClose(tab: model.tabs[0])
        await model.answer(.save)

        #expect(model.tabs.isEmpty)
        #expect(try await files.read(path("hello.txt"), maxBytes: 100) == "hello")
    }

    @Test func cancellingThePanelFromTheCloseQuestionKeepsTheTab() async throws {
        _ = try await start()
        await model.newUntitled()
        try type("hello")

        await model.requestClose(tab: model.tabs[0])
        await model.answer(.save)

        #expect(names == ["Untitled"])
    }

    @Test func saveAllWritesFilesFirstThenAsksForEachUntitledTab() async throws {
        _ = try await start(with: ["a.txt": "one"])
        await model.open(url("a.txt"))
        try type("!")
        await model.newUntitled()
        try type("first")
        await model.newUntitled()
        try type("second")
        picker.script(url("one.txt"))
        picker.script(url("two.txt"))

        #expect(model.unsavedFiles.sorted() == ["Untitled", "Untitled 2", "a.txt"])
        #expect(await model.saveAll())

        #expect(try await files.read(path("a.txt"), maxBytes: 100) == "one!")
        #expect(try await files.read(path("one.txt"), maxBytes: 100) == "first")
        #expect(try await files.read(path("two.txt"), maxBytes: 100) == "second")
        #expect(model.unsavedFiles.isEmpty)
    }

    @Test func cancellingAnyPanelStopsSaveAll() async throws {
        _ = try await start()
        await model.newUntitled()
        try type("first")
        await model.newUntitled()
        try type("second")
        picker.script(url("one.txt"))
        picker.script(nil)

        #expect(await model.saveAll() == false)
    }

    // MARK: - Persistence

    @Test func untitledTabsAreNeverWrittenIntoTheSavedState() async throws {
        let state = try await start(with: ["a.txt": "one"])
        await model.open(url("a.txt"))
        await model.newUntitled()
        try type("hello")

        let data = try state.uiState(EditorUIState.self).encode()
        let json = String(decoding: data, as: UTF8.self)

        #expect(json.contains("a.txt"))
        #expect(json.contains("Untitled") == false)
    }
}
