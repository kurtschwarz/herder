import Core
import Foundation
import TestSupport
import Testing

@testable import EditorFeature

@Suite @MainActor struct EditorEditingTests {
    let files = InMemoryFileClient()
    let watcher = StubFileWatcherClient()
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
        model = EditorModel(store: store, files: files, highlighter: NoSyntaxHighlighter())
    }

    func path(_ name: String) -> String { root.appending(path: name).path(percentEncoded: false) }
    func url(_ name: String) -> URL { root.appending(path: name) }

    func start(with texts: [String: String]) async throws -> Workspace {
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

    func settle() async {
        for _ in 0..<500 { await Task.yield() }
    }

    /// What the person using the view does: change the storage, then the
    /// buffer reports it. Stands in for keystrokes, which need a window.
    func type(_ text: String, at location: Int? = nil) throws {
        let buffer = try #require(model.activeBuffer)
        let at = location ?? buffer.storage.length
        buffer.storage.replaceCharacters(in: NSRange(location: at, length: 0), with: text)
        model.bufferDidChange(buffer)
    }

    var text: String { model.activeBuffer?.text ?? "" }

    // MARK: - Dirty

    @Test func openingAFileDoesNotMakeItDirty() async throws {
        _ = try await start(with: ["a.txt": "one"])

        await model.open(url("a.txt"))

        #expect(model.isDirty(PathKey(canonical: path("a.txt"))) == false)
        #expect(model.canSave == false)
    }

    @Test func typingMakesTheTabDirtyAndTypingItBackMakesItCleanAgain() async throws {
        _ = try await start(with: ["a.txt": "one"])
        await model.open(url("a.txt"))

        try type("!")
        #expect(model.isDirty(PathKey(canonical: path("a.txt"))))
        #expect(model.canSave)

        let buffer = try #require(model.activeBuffer)
        buffer.storage.deleteCharacters(in: NSRange(location: 3, length: 1))
        model.bufferDidChange(buffer)
        #expect(model.isDirty(PathKey(canonical: path("a.txt"))) == false)
    }

    @Test func aBackgroundTabKeepsWhatWasTypedInIt() async throws {
        _ = try await start(with: ["a.txt": "one", "b.txt": "two"])
        await model.open(url("a.txt"))
        try type(" more")
        let buffer = model.activeBuffer

        await model.open(url("b.txt"))
        #expect(model.isDirty(PathKey(canonical: path("a.txt"))))
        await model.activate(PathKey(canonical: path("a.txt")))

        #expect(text == "one more")
        #expect(model.activeBuffer === buffer)
        #expect(model.isDirty(PathKey(canonical: path("a.txt"))))
    }

    // MARK: - Saving

    @Test func savingWritesTheBufferExactly() async throws {
        _ = try await start(with: ["a.txt": "one\r\ntwo"])
        await model.open(url("a.txt"))
        try type("!", at: 3)

        await model.save()

        // No final newline added and the CRLF left alone.
        #expect(files.writes == [.init(path: path("a.txt"), contents: "one!\r\ntwo")])
        #expect(model.canSave == false)
        #expect(model.saveFailure == nil)
    }

    @Test func theReadThatFollowsOurOwnSaveChangesNothing() async throws {
        _ = try await start(with: ["a.txt": "one"])
        await model.open(url("a.txt"))
        try type("!")
        await model.save()

        watcher.change([root])
        await settle()

        #expect(text == "one!")
        #expect(model.activeDocument?.isStale == false)
        #expect(model.canSave == false)
    }

    @Test func aFailedSaveLeavesTheTabDirtyAndSaysWhy() async throws {
        struct Refused: LocalizedError { var errorDescription: String? { "Disk full." } }
        _ = try await start(with: ["a.txt": "one"])
        await model.open(url("a.txt"))
        try type("!")
        files.refuseWrites(with: Refused())

        await model.save()

        #expect(model.canSave)
        #expect(model.saveFailure == SaveFailure(name: "a.txt", reason: "Disk full."))

        model.dismissSaveFailure()
        #expect(model.saveFailure == nil)
    }

    @Test func savingADeletedFileWritesItBack() async throws {
        _ = try await start(with: ["a.txt": "one"])
        await model.open(url("a.txt"))
        files.seed(children: [], of: root)
        watcher.change([root])
        await settle()
        #expect(model.isDeleted)

        try type("!")
        await model.save()

        #expect(files.files[path("a.txt")] == "one!")
        #expect(model.isDeleted == false)
    }

    @Test func savingWillNotMakeBackAFolderThatWasDeleted() async throws {
        let sub = url("sub")
        files.seed(path("sub/a.txt"), "one")
        files.seed(children: [DirectoryEntry(url: sub, isDirectory: true)], of: root)
        files.seed(children: [DirectoryEntry(url: sub.appending(path: "a.txt"), isDirectory: false)], of: sub)
        store.display(WorkspaceID(root), from: window)
        let state = try #require(await store.open(WorkspaceID(root)))
        await state.open(PathKey(canonical: path("sub")))
        await state.refresh()
        await model.restore(in: state)
        await model.open(url("sub/a.txt"))
        try type("!")

        files.seed(children: [], of: root)
        await state.refresh()
        await model.save()

        #expect(files.writes.isEmpty)
        #expect(model.saveFailure?.name == "a.txt")
        #expect(model.canSave)
    }

    // MARK: - The disk changing underneath

    @Test func aCleanBufferTakesWhatChangedOnDisk() async throws {
        _ = try await start(with: ["a.txt": "one"])
        await model.open(url("a.txt"))

        files.seed(path("a.txt"), "outside")
        watcher.change([root])
        await settle()

        #expect(text == "outside")
        #expect(model.activeDocument?.isStale == false)
    }

    @Test func aDirtyBufferIsNeverReplacedAndIsMarkedStale() async throws {
        _ = try await start(with: ["a.txt": "one"])
        await model.open(url("a.txt"))
        try type("!")

        files.seed(path("a.txt"), "outside")
        watcher.change([root])
        await settle()

        #expect(text == "one!")
        #expect(model.activeDocument?.isStale == true)
        #expect(model.canSave)
    }

    // MARK: - Renaming

    @Test func renamingCarriesTheUnsavedTextWithIt() async throws {
        let state = try await start(with: ["a.txt": "one"])
        await model.open(url("a.txt"))
        try type("!")
        let buffer = model.activeBuffer
        files.seed(path("b.txt"), "one")

        try await state.move(url("a.txt"), to: url("b.txt"))
        await settle()

        #expect(model.activeBuffer === buffer)
        #expect(text == "one!")
        #expect(model.isDirty(PathKey(canonical: path("b.txt"))))
    }

    @Test func keepingEditsClearsStaleAndSavingThenReplacesTheDisk() async throws {
        _ = try await start(with: ["a.txt": "one"])
        await model.open(url("a.txt"))
        try type("!")
        files.seed(path("a.txt"), "outside")
        watcher.change([root])
        await settle()
        #expect(model.isStale)

        await model.keepEdits()
        #expect(model.isStale == false)
        #expect(text == "one!")

        await model.save()
        #expect(files.files[path("a.txt")] == "one!")
    }

    @Test func reloadingFromDiskDropsTheEditsAndTakesTheDisk() async throws {
        _ = try await start(with: ["a.txt": "one"])
        await model.open(url("a.txt"))
        try type("!")
        files.seed(path("a.txt"), "outside")
        watcher.change([root])
        await settle()

        await model.reloadFromDisk()

        #expect(text == "outside")
        #expect(model.isStale == false)
        #expect(model.canSave == false)
    }

    // MARK: - Closing

    @Test func closingACleanTabDoesNotAsk() async throws {
        _ = try await start(with: ["a.txt": "one"])
        await model.open(url("a.txt"))

        await model.closeActiveTab()

        #expect(model.closePrompt == nil)
        #expect(model.tabs.isEmpty)
    }

    @Test func closingADirtyTabAsksAndLeavesItOpen() async throws {
        _ = try await start(with: ["a.txt": "one"])
        await model.open(url("a.txt"))
        try type("!")

        await model.closeActiveTab()

        #expect(model.closePrompt == .init(key: PathKey(canonical: path("a.txt"))))
        #expect(model.tabs.count == 1)
    }

    @Test func cancellingTheQuestionKeepsTheTabAndItsEdits() async throws {
        _ = try await start(with: ["a.txt": "one"])
        await model.open(url("a.txt"))
        try type("!")
        await model.closeActiveTab()

        await model.answer(.cancel)

        #expect(model.closePrompt == nil)
        #expect(model.tabs.count == 1)
        #expect(text == "one!")
    }

    @Test func discardingClosesWithoutWriting() async throws {
        _ = try await start(with: ["a.txt": "one"])
        await model.open(url("a.txt"))
        try type("!")
        await model.closeActiveTab()

        await model.answer(.discard)

        #expect(model.tabs.isEmpty)
        #expect(files.writes.isEmpty)
        #expect(model.documents.documents.isEmpty)
    }

    @Test func savingThenClosingWritesFirst() async throws {
        _ = try await start(with: ["a.txt": "one"])
        await model.open(url("a.txt"))
        try type("!")
        await model.closeActiveTab()

        await model.answer(.save)

        #expect(files.files[path("a.txt")] == "one!")
        #expect(model.tabs.isEmpty)
    }

    @Test func aFailedSaveWhileClosingKeepsTheTabOpen() async throws {
        struct Refused: LocalizedError { var errorDescription: String? { "Disk full." } }
        _ = try await start(with: ["a.txt": "one"])
        await model.open(url("a.txt"))
        try type("!")
        await model.closeActiveTab()
        files.refuseWrites(with: Refused())

        await model.answer(.save)

        #expect(model.tabs.count == 1)
        #expect(model.saveFailure != nil)
        #expect(text == "one!")
    }

    @Test func everyDirtyFileIsListedAndSavedTogether() async throws {
        _ = try await start(with: ["a.txt": "one", "b.txt": "two", "c.txt": "three"])
        await model.open(url("a.txt"))
        try type("!")
        await model.open(url("b.txt"))
        try type("?")
        await model.open(url("c.txt"))

        #expect(model.unsavedFiles.sorted() == ["a.txt", "b.txt"])
        #expect(await model.saveAll())

        #expect(files.files[path("a.txt")] == "one!")
        #expect(files.files[path("b.txt")] == "two?")
        #expect(model.unsavedFiles.isEmpty)
    }

    @Test func closingATabFreesItsBuffer() async throws {
        _ = try await start(with: ["a.txt": "one"])
        await model.open(url("a.txt"))

        await model.close(tab: PathKey(canonical: path("a.txt")))

        #expect(model.documents.documents.isEmpty)
        #expect(model.activeBuffer == nil)
    }

    @Test func unavailableFilesAreNotEditable() async throws {
        _ = try await start(with: ["big.log": "x"])
        files.seed(path("big.log"), String(repeating: "x", count: EditorModel.maxBytes + 1))

        await model.open(url("big.log"))

        #expect(model.activeBuffer == nil)
        #expect(model.canSave == false)
    }
}
