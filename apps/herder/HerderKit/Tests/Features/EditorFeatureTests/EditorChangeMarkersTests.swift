import Core
import Foundation
import TestSupport
import Testing

@testable import EditorFeature

@Suite @MainActor struct EditorChangeMarkersTests {
    let files = InMemoryFileClient()
    let git = StubGitClient()
    let watcher = StubFileWatcherClient()
    let store: WorkspaceRegistry
    let model: EditorModel
    let root = URL(filePath: "/code/api")
    let window = NSObject()

    init() {
        store = WorkspaceRegistry(
            files: files,
            git: git,
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

    func type(_ text: String, at location: Int? = nil) throws {
        let buffer = try #require(model.activeBuffer)
        let at = location ?? buffer.storage.length
        buffer.storage.replaceCharacters(in: NSRange(location: at, length: 0), with: text)
        model.bufferDidChange(buffer)
    }

    /// The markers are worked out off the main actor, so they arrive a moment
    /// after whatever asked for them. Waits for them to read `expected`, up to
    /// a few seconds, and answers what they read when it stopped waiting.
    func markers(becoming expected: LineChanges) async -> LineChanges? {
        for _ in 0..<400 {
            if model.activeBuffer?.changes == expected { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return model.activeBuffer?.changes
    }

    // MARK: - Opening

    @Test func openingAFileWithUncommittedChangesMarksThem() async throws {
        git.seed(contents: "a\nb\nc\n", of: url("a.txt"))
        _ = try await start(with: ["a.txt": "a\nB\nc\nd\n"])

        await model.open(url("a.txt"))

        let expected = LineChanges(base: "a\nb\nc\n", current: "a\nB\nc\nd\n")
        #expect(expected.modified == IndexSet(integer: 2))
        #expect(expected.added == IndexSet(integer: 4))
        #expect(await markers(becoming: expected) == expected)
    }

    @Test func aCleanFileHasNoMarkers() async throws {
        git.seed(contents: "a\nb\n", of: url("a.txt"))
        _ = try await start(with: ["a.txt": "a\nb\n"])

        await model.open(url("a.txt"))

        #expect(model.activeBuffer?.changes == LineChanges.none)
    }

    @Test func aFileStagedAsNewHasEveryLineAdded() async throws {
        git.seed(status: ["new.txt": .tracked(staged: .added, unstaged: .unchanged)], in: root)
        _ = try await start(with: ["new.txt": "a\nb\n"])

        await model.open(url("new.txt"))

        let expected = LineChanges(base: "", current: "a\nb\n")
        #expect(await markers(becoming: expected) == expected)
        #expect(expected.added == IndexSet(1...2))
    }

    // MARK: - Typing

    @Test func typingUpdatesTheMarkersWithoutSaving() async throws {
        git.seed(contents: "a\nb\n", of: url("a.txt"))
        _ = try await start(with: ["a.txt": "a\nb\n"])
        await model.open(url("a.txt"))

        try type("c\n")

        let expected = LineChanges(base: "a\nb\n", current: "a\nb\nc\n")
        #expect(await markers(becoming: expected) == expected)
        #expect(model.isDirty(PathKey(canonical: path("a.txt"))))
    }

    @Test func typingItBackClearsTheMarkers() async throws {
        git.seed(contents: "a\nb\n", of: url("a.txt"))
        _ = try await start(with: ["a.txt": "a\nb\n"])
        await model.open(url("a.txt"))
        try type("c\n")
        _ = await markers(becoming: LineChanges(base: "a\nb\n", current: "a\nb\nc\n"))

        let buffer = try #require(model.activeBuffer)
        buffer.storage.deleteCharacters(in: NSRange(location: 4, length: 2))
        model.bufferDidChange(buffer)

        #expect(await markers(becoming: .none) == LineChanges.none)
    }

    // MARK: - Nothing to compare with

    @Test func anUntrackedFileHasNoMarkers() async throws {
        git.seed(status: ["u.txt": .untracked], in: root)
        git.seed(contents: "old\n", of: url("u.txt"))
        _ = try await start(with: ["u.txt": "new\n"])

        await model.open(url("u.txt"))

        #expect(model.activeBuffer?.changes == LineChanges.none)
        #expect(git.contentLookups.isEmpty)
    }

    @Test func aFileInAConflictHasNoMarkers() async throws {
        git.seed(status: ["c.txt": .unmerged], in: root)
        git.seed(contents: "old\n", of: url("c.txt"))
        _ = try await start(with: ["c.txt": "new\n"])

        await model.open(url("c.txt"))

        #expect(model.activeBuffer?.changes == LineChanges.none)
    }

    @Test func aFileWithNoTextInHeadHasNoMarkers() async throws {
        git.seed(contents: nil, of: url("a.txt"))
        _ = try await start(with: ["a.txt": "new\n"])

        await model.open(url("a.txt"))

        #expect(model.activeBuffer?.changes == LineChanges.none)
    }

    @Test func gitFailingLeavesNoMarkers() async throws {
        git.failContentLookups()
        _ = try await start(with: ["a.txt": "new\n"])

        await model.open(url("a.txt"))

        #expect(model.activeBuffer?.changes == LineChanges.none)
    }

    @Test func anUntitledTabHasNoMarkers() async throws {
        _ = try await start(with: ["a.txt": "a\n"])

        await model.newUntitled()
        try type("typed\n")

        try? await Task.sleep(for: .milliseconds(300))
        #expect(model.activeBuffer?.changes == LineChanges.none)
    }

    @Test func aFileTooBigToCompareHasNoMarkers() async throws {
        let big = String(repeating: "a\n", count: LineChanges.maxLines + 1)
        git.seed(contents: big, of: url("big.txt"))
        _ = try await start(with: ["big.txt": big])

        await model.open(url("big.txt"))
        try type("more\n")

        try? await Task.sleep(for: .milliseconds(300))
        #expect(model.activeBuffer?.changes == LineChanges.none)
    }

    // MARK: - Fetching the base again

    @Test func theBaseIsFetchedAgainOnAWorkspaceRefresh() async throws {
        git.seed(contents: "a\nb\n", of: url("a.txt"))
        let state = try await start(with: ["a.txt": "a\nb\nc\n"])
        await model.open(url("a.txt"))
        _ = await markers(becoming: LineChanges(base: "a\nb\n", current: "a\nb\nc\n"))
        let lookups = git.contentLookups.count

        // A commit: HEAD now has the third line.
        git.seed(contents: "a\nb\nc\n", of: url("a.txt"))
        await state.refresh()

        #expect(await markers(becoming: .none) == LineChanges.none)
        #expect(git.contentLookups.count > lookups)
    }

    @Test func aTabFetchesItsBaseWhenItBecomesVisible() async throws {
        git.seed(contents: "one\n", of: url("a.txt"))
        git.seed(contents: "two\n", of: url("b.txt"))
        _ = try await start(with: ["a.txt": "one\n", "b.txt": "TWO\n"])
        await model.open(url("a.txt"))
        #expect(git.contentLookups.map(\.lastPathComponent) == ["a.txt"])

        await model.open(url("b.txt"))

        let expected = LineChanges(base: "two\n", current: "TWO\n")
        #expect(await markers(becoming: expected) == expected)
        #expect(git.contentLookups.map(\.lastPathComponent).contains("b.txt"))
    }
}
