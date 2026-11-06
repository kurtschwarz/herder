import Core
import Foundation
import Services
import TestSupport
import Testing

@testable import EditorFeature

/// Which file a workspace had open, across a switch and across a launch.
@Suite struct EditorRestorationTests {
    let files = InMemoryFileClient()
    let git = StubGitClient()
    let watcher = StubFileWatcherClient()
    let clock = VirtualClockClient()
    let state = InMemoryStateStore()
    let root = URL(filePath: "/code/api")
    let other = URL(filePath: "/code/web")

    init() {
        for folder in [root, other] {
            for name in ["a.txt", "b.txt", "c.txt"] {
                files.seed(folder.appending(path: name).path(percentEncoded: false), "\(folder.lastPathComponent) \(name)")
            }
            files.seed(
                children: ["a.txt", "b.txt", "c.txt"].map { DirectoryEntry(url: folder.appending(path: $0), isDirectory: false) },
                of: folder
            )
        }
    }

    func makeRegistry(files: InMemoryFileClient? = nil) -> WorkspaceRegistry {
        WorkspaceRegistry(files: files ?? self.files, git: git, watcher: watcher, clock: clock, state: state)
    }

    func makeModel(_ registry: WorkspaceRegistry, files: InMemoryFileClient? = nil) -> EditorModel {
        EditorModel(store: registry, files: files ?? self.files, highlighter: TreeSitterHighlighter())
    }

    /// Opens `name` in the editor with `workspace` open, then puts the
    /// workspace away, which is what writes it down.
    func openAndQuit(_ name: String) async throws {
        let registry = makeRegistry()
        let model = makeModel(registry)
        _ = await registry.open(WorkspaceID(root))
        await model.open(root.appending(path: name))
        await registry.close(WorkspaceID(root))
    }

    func plain(_ text: String) -> EditorModel.Content {
        .text(SourceText(text: text))
    }

    @Test func aWorkspaceWithNothingRememberedOpensEmpty() async throws {
        let registry = makeRegistry()
        let model = makeModel(registry)

        await model.restore(in: await registry.open(WorkspaceID(root)))

        #expect(model.file == nil)
    }

    @Test func noWorkspaceEmptiesThePane() async throws {
        let registry = makeRegistry()
        let model = makeModel(registry)
        await registry.open(WorkspaceID(root))
        await model.open(root.appending(path: "a.txt"))

        await model.restore(in: nil)

        #expect(model.file == nil)
    }

    @Test func openingAFileRecordsItOnTheWorkspace() async throws {
        let registry = makeRegistry()
        let model = makeModel(registry)
        let workspace = try #require(await registry.open(WorkspaceID(root)))

        await model.open(root.appending(path: "a.txt"))

        let state = workspace.uiState(EditorUIState.self)
        #expect(state.files == [PathKey(root.appending(path: "a.txt"))])
        #expect(state.active == PathKey(root.appending(path: "a.txt")))
    }

    /// Switching away and back lands on the file left open, which the pane
    /// used to throw away on every switch.
    @Test func comingBackToAWorkspaceReopensItsFile() async throws {
        let registry = makeRegistry()
        let model = makeModel(registry)
        let api = await registry.open(WorkspaceID(root))
        let web = await registry.open(WorkspaceID(other))
        await model.restore(in: api)
        await model.open(root.appending(path: "b.txt"))

        await model.restore(in: web)
        #expect(model.file == nil)
        await model.open(other.appending(path: "a.txt"))
        await model.restore(in: api)

        #expect(model.file == root.appending(path: "b.txt"))
        #expect(model.content == plain("api b.txt"))
    }

    @Test func aRelaunchReopensTheFile() async throws {
        try await openAndQuit("b.txt")

        let relaunched = makeRegistry()
        let fresh = makeModel(relaunched)
        await fresh.restore(in: await relaunched.open(WorkspaceID(root)))

        #expect(fresh.file == root.appending(path: "b.txt"))
        #expect(fresh.content == plain("api b.txt"))
    }

    /// Gone while the app was shut: the breadcrumb is all there is left to
    /// show, struck through, and the path is still remembered.
    @Test func aRememberedFileThatHasGoneShowsAsDeleted() async throws {
        try await openAndQuit("b.txt")
        let after = InMemoryFileClient()
        after.seed(root.appending(path: "a.txt").path(percentEncoded: false), "api a.txt")
        after.seed(children: [DirectoryEntry(url: root.appending(path: "a.txt"), isDirectory: false)], of: root)

        let relaunched = makeRegistry(files: after)
        let fresh = makeModel(relaunched, files: after)
        let workspace = try #require(await relaunched.open(WorkspaceID(root)))
        await fresh.restore(in: workspace)

        #expect(fresh.file == root.appending(path: "b.txt"))
        #expect(fresh.isDeleted)
        #expect(fresh.content == nil)
        #expect(workspace.uiState(EditorUIState.self).active == PathKey(root.appending(path: "b.txt")))
    }

    /// Opening a second file leaves the first open, which is the whole point
    /// of the bar — and both are written down.
    @Test func everyTabIsRemembered() async throws {
        let registry = makeRegistry()
        let model = makeModel(registry)
        let workspace = try #require(await registry.open(WorkspaceID(root)))
        await model.open(root.appending(path: "a.txt"))
        await model.open(root.appending(path: "b.txt"))

        let state = workspace.uiState(EditorUIState.self)
        #expect(state.files == ["a.txt", "b.txt"].map { PathKey(root.appending(path: $0)) })
        #expect(state.active == PathKey(root.appending(path: "b.txt")))
    }

    /// Everything comes back, but only the tab that was showing is read: the
    /// rest are names until they are clicked.
    @Test func aRelaunchReopensEveryTabAndReadsOnlyTheOneShowing() async throws {
        let registry = makeRegistry()
        let model = makeModel(registry)
        _ = await registry.open(WorkspaceID(root))
        for name in ["a.txt", "b.txt", "c.txt"] {
            await model.open(root.appending(path: name))
        }
        await model.open(root.appending(path: "b.txt"))
        await registry.close(WorkspaceID(root))

        let reads = InMemoryFileClient()
        for name in ["a.txt", "b.txt", "c.txt"] {
            reads.seed(root.appending(path: name).path(percentEncoded: false), "api \(name)")
        }
        reads.seed(
            children: ["a.txt", "b.txt", "c.txt"].map { DirectoryEntry(url: root.appending(path: $0), isDirectory: false) },
            of: root
        )
        let relaunched = makeRegistry(files: reads)
        let fresh = makeModel(relaunched, files: reads)
        reads.clearReads()
        await fresh.restore(in: await relaunched.open(WorkspaceID(root)))

        #expect(fresh.tabs == ["a.txt", "b.txt", "c.txt"].map { PathKey(root.appending(path: $0)) })
        #expect(fresh.file == root.appending(path: "b.txt"))
        #expect(reads.reads == [root.appending(path: "b.txt").path(percentEncoded: false)])
    }
}
