import Clients
import ClientsTestSupport
import Foundation
import Models
import Testing
import Worktrees

@testable import EditorFeature

@Suite struct EditorModelTests {
    let files = InMemoryFileClient()
    let git = StubGitClient()
    let watcher = StubFileWatcherClient()
    let clock = VirtualClockClient()
    let store: WorktreeStateStore
    let model: EditorModel
    let root = URL(filePath: "/code/api")

    init() {
        store = WorktreeStateStore(files: files, git: git, watcher: watcher, clock: clock)
        model = EditorModel(store: store, files: files)
    }

    func file(_ name: String) -> DirectoryEntry {
        DirectoryEntry(url: root.appending(path: name), isDirectory: false)
    }

    func path(_ name: String) -> String {
        root.appending(path: name).path(percentEncoded: false)
    }

    /// Selects `root` with `names` in it, each holding its own name as text.
    func start(with names: [String]) async throws -> WorktreeState {
        for name in names { files.seed(path(name), "contents of \(name)") }
        files.seed(children: names.map(file), of: root)
        let state = try #require(await store.select(root))
        await state.refresh()
        return state
    }

    func settle() async {
        for _ in 0..<500 { await Task.yield() }
    }

    @Test func openingAFileShowsItsText() async throws {
        _ = try await start(with: ["a.txt"])

        await model.open(root.appending(path: "a.txt"))

        #expect(model.content == .text("contents of a.txt"))
        #expect(model.breadcrumb == ["api", "a.txt"])
    }

    @Test func aFileOutsideEveryWorktreeIsNotOpened() async throws {
        _ = try await start(with: ["a.txt"])

        await model.open(URL(filePath: "/elsewhere/b.txt"))

        #expect(model.file == nil)
    }

    @Test func aFileOverTheCeilingGetsAReasonNotItsText() async throws {
        _ = try await start(with: ["big.log"])
        files.seed(path("big.log"), String(repeating: "x", count: EditorModel.maxBytes + 1))

        await model.open(root.appending(path: "big.log"))

        #expect(model.content == .unavailable(.tooLarge))
    }

    @Test func aChangeToTheFileReReadsIt() async throws {
        _ = try await start(with: ["a.txt"])
        await model.open(root.appending(path: "a.txt"))

        files.seed(path("a.txt"), "rewritten")
        watcher.change([root])
        await settle()

        #expect(model.content == .text("rewritten"))
    }

    @Test func aFileThatGoesStaysOpenAndIsMarkedDeleted() async throws {
        _ = try await start(with: ["a.txt"])
        await model.open(root.appending(path: "a.txt"))

        files.seed(children: [], of: root)
        watcher.change([root])
        await settle()

        #expect(model.isDeleted)
        #expect(model.content == .text("contents of a.txt"))
    }

    @Test func aDeletedFileThatComesBackIsReadAgain() async throws {
        _ = try await start(with: ["a.txt"])
        await model.open(root.appending(path: "a.txt"))
        files.seed(children: [], of: root)
        watcher.change([root])
        await settle()

        files.seed(path("a.txt"), "regenerated")
        files.seed(children: [file("a.txt")], of: root)
        watcher.change([root])
        await settle()

        #expect(!model.isDeleted)
        #expect(model.content == .text("regenerated"))
    }

    @Test func renamingTheOpenFileFollowsIt() async throws {
        let state = try await start(with: ["a.txt"])
        files.seed(path("b.txt"), "contents of a.txt")
        await model.open(root.appending(path: "a.txt"))

        try await state.move(root.appending(path: "a.txt"), to: root.appending(path: "b.txt"))

        #expect(model.file == root.appending(path: "b.txt"))
        #expect(!model.isDeleted)
        #expect(model.breadcrumb == ["api", "b.txt"])
    }

    @Test func closingEmptiesThePane() async throws {
        _ = try await start(with: ["a.txt"])
        await model.open(root.appending(path: "a.txt"))

        model.close()

        #expect(model.file == nil)
        #expect(model.content == nil)
    }

    @Test func openingTheOpenFileAgainKeepsTheSession() async throws {
        _ = try await start(with: ["a.txt"])
        await model.open(root.appending(path: "a.txt"))
        let session = model.session

        await model.open(root.appending(path: "a.txt"))

        #expect(model.session == session)
    }
}
