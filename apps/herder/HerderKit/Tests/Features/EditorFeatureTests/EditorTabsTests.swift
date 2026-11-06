import Core
import Foundation
import TestSupport
import Testing

@testable import EditorFeature

/// What the tab bar is: the set of files open, which one is showing, and what
/// the two do when files are closed or renamed underneath them.
@Suite struct EditorTabsTests {
    let files = InMemoryFileClient()
    let git = StubGitClient()
    let watcher = StubFileWatcherClient()
    let clock = VirtualClockClient()
    let state = InMemoryStateStore()
    let root = URL(filePath: "/code/api")

    /// `a.txt`, `b.txt`, `c.txt` at the root, plus `api/index.ts` and
    /// `web/index.ts` for the two tabs that read the same.
    init() {
        var entries = ["a.txt", "b.txt", "c.txt"].map {
            DirectoryEntry(url: root.appending(path: $0), isDirectory: false)
        }
        for name in ["a.txt", "b.txt", "c.txt"] {
            files.seed(root.appending(path: name).path(percentEncoded: false), name)
        }
        for folder in ["api", "web"] {
            let url = root.appending(path: folder)
            entries.append(DirectoryEntry(url: url, isDirectory: true))
            files.seed(url.appending(path: "index.ts").path(percentEncoded: false), "\(folder) index")
            files.seed(
                children: [DirectoryEntry(url: url.appending(path: "index.ts"), isDirectory: false)],
                of: url
            )
        }
        files.seed(children: entries, of: root)
    }

    func makeModel() -> (EditorModel, WorkspaceRegistry) {
        let registry = WorkspaceRegistry(files: files, git: git, watcher: watcher, clock: clock, state: state)
        return (EditorModel(store: registry, files: files, highlighter: NoSyntaxHighlighter()), registry)
    }

    /// Opens the workspace and the named files, leaving the last one showing.
    func open(_ names: [String]) async -> (EditorModel, WorkspaceRegistry) {
        let (model, registry) = makeModel()
        await registry.open(WorkspaceID(root))
        for name in names {
            await model.open(root.appending(path: name))
        }
        return (model, registry)
    }

    func key(_ name: String) -> PathKey {
        PathKey(root.appending(path: name))
    }

    @Test func eachOpenAddsATabAndShowsIt() async throws {
        let (model, _) = await open(["a.txt", "b.txt"])

        #expect(model.tabs == [key("a.txt"), key("b.txt")])
        #expect(model.activeTab == key("b.txt"))
    }

    /// A repeat click does not open a second tab, and does not restart the
    /// read behind the one it has.
    @Test func openingAFileThatHasATabShowsItAgain() async throws {
        let (model, _) = await open(["a.txt", "b.txt", "a.txt"])

        #expect(model.tabs == [key("a.txt"), key("b.txt")])
        #expect(model.activeTab == key("a.txt"))
    }

    @Test func closingTheTabShowingGoesRight() async throws {
        let (model, _) = await open(["a.txt", "b.txt", "c.txt", "b.txt"])

        await model.close(tab: key("b.txt"))

        #expect(model.tabs == [key("a.txt"), key("c.txt")])
        #expect(model.activeTab == key("c.txt"))
    }

    /// There is no right neighbour at the end.
    @Test func closingTheLastTabShowingGoesLeft() async throws {
        let (model, _) = await open(["a.txt", "b.txt"])

        await model.close(tab: key("b.txt"))

        #expect(model.tabs == [key("a.txt")])
        #expect(model.activeTab == key("a.txt"))
    }

    @Test func closingTheOnlyTabEmptiesThePane() async throws {
        let (model, _) = await open(["a.txt"])

        await model.close(tab: key("a.txt"))

        #expect(model.tabs.isEmpty)
        #expect(model.activeTab == nil)
        #expect(model.file == nil)
        #expect(model.content == nil)
    }

    @Test func closingABackgroundTabLeavesTheOneShowingAlone() async throws {
        let (model, _) = await open(["a.txt", "b.txt"])

        await model.close(tab: key("a.txt"))

        #expect(model.tabs == [key("b.txt")])
        #expect(model.activeTab == key("b.txt"))
    }

    @Test func cyclingWrapsAtBothEnds() async throws {
        let (model, _) = await open(["a.txt", "b.txt", "c.txt"])

        await model.selectNextTab()
        #expect(model.activeTab == key("a.txt"))

        await model.selectPreviousTab()
        #expect(model.activeTab == key("c.txt"))
    }

    @Test func cyclingWithOneTabDoesNothing() async throws {
        let (model, _) = await open(["a.txt"])

        await model.selectNextTab()

        #expect(model.activeTab == key("a.txt"))
    }

    /// Leaving a checkout drops the tabs, because the next one has its own.
    @Test func closingThePaneDropsEveryTab() async throws {
        let (model, _) = await open(["a.txt", "b.txt"])

        model.close()

        #expect(model.tabs.isEmpty)
        #expect(model.file == nil)
    }

    // MARK: - Reordering

    @Test func movingATabChangesTheOrder() async throws {
        let (model, _) = await open(["a.txt", "b.txt", "c.txt"])

        model.move(key("a.txt"), to: 2)
        #expect(model.tabs == [key("b.txt"), key("c.txt"), key("a.txt")])

        model.move(key("a.txt"), to: 0)
        #expect(model.tabs == [key("a.txt"), key("b.txt"), key("c.txt")])
    }

    /// Selection is navigation and wraps; a move would teleport the tab.
    @Test func movingTheActiveTabStopsAtBothEnds() async throws {
        let (model, _) = await open(["a.txt", "b.txt", "c.txt"])
        #expect(model.activeTab == key("c.txt"))

        #expect(!model.canMoveActiveTab(by: 1))
        model.moveActiveTab(by: 1)
        #expect(model.tabs == [key("a.txt"), key("b.txt"), key("c.txt")])

        model.moveActiveTab(by: -1)
        model.moveActiveTab(by: -1)
        #expect(model.tabs == [key("c.txt"), key("a.txt"), key("b.txt")])

        #expect(!model.canMoveActiveTab(by: -1))
        model.moveActiveTab(by: -1)
        #expect(model.tabs == [key("c.txt"), key("a.txt"), key("b.txt")])
    }

    @Test func movingWithFewerThanTwoTabsDoesNothing() async throws {
        let (empty, _) = await open([])
        empty.moveActiveTab(by: 1)
        #expect(empty.tabs.isEmpty)
        #expect(!empty.canMoveActiveTab(by: 1))

        let (one, _) = await open(["a.txt"])
        one.moveActiveTab(by: -1)
        one.move(key("a.txt"), to: 5)
        #expect(one.tabs == [key("a.txt")])
        #expect(!one.canMoveActiveTab(by: -1))
    }

    /// Putting a tab down is not looking at it.
    @Test func movingATabLeavesTheOneShowingAlone() async throws {
        let (model, _) = await open(["a.txt", "b.txt", "c.txt"])

        model.move(key("a.txt"), to: 2)
        #expect(model.activeTab == key("c.txt"))

        model.moveActiveTab(by: -1)
        #expect(model.activeTab == key("c.txt"))
    }

    @Test func aMoveOutlivesTheWindow() async throws {
        let (model, registry) = await open(["a.txt", "b.txt", "c.txt"])
        let workspace = try #require(registry.workspace(for: WorkspaceID(root)))

        model.move(key("a.txt"), to: 2)

        let stored = EditorUIState()
        try stored.restore(from: try workspace.uiState(EditorUIState.self).encode())
        #expect(stored.files == [key("b.txt"), key("c.txt"), key("a.txt")])

        let reopened = EditorModel(store: registry, files: files, highlighter: NoSyntaxHighlighter())
        await reopened.restore(in: workspace)
        #expect(reopened.tabs == [key("b.txt"), key("c.txt"), key("a.txt")])
        #expect(reopened.activeTab == key("c.txt"))
    }

    // MARK: - Renames

    @Test func aRenameCarriesEveryTabAlong() async throws {
        let (model, registry) = await open(["a.txt", "b.txt"])
        let workspace = try #require(registry.workspace(for: WorkspaceID(root)))

        try await workspace.move(root.appending(path: "a.txt"), to: root.appending(path: "z.txt"))

        #expect(model.tabs == [key("z.txt"), key("b.txt")])
        #expect(model.activeTab == key("b.txt"))
    }

    /// Two tabs on one path is a state with no correct rendering.
    @Test func aRenameOntoAnOpenTabCollapsesTheTwo() async throws {
        let (model, registry) = await open(["b.txt", "a.txt"])
        let workspace = try #require(registry.workspace(for: WorkspaceID(root)))
        files.seed(children: [DirectoryEntry(url: root.appending(path: "a.txt"), isDirectory: false)], of: root)

        try await workspace.move(root.appending(path: "a.txt"), to: root.appending(path: "b.txt"))

        #expect(model.tabs == [key("b.txt")])
        #expect(model.activeTab == key("b.txt"))
    }

    @Test func renamingAFolderCarriesTheTabsBelowIt() async throws {
        let (model, registry) = await open(["api/index.ts"])
        let workspace = try #require(registry.workspace(for: WorkspaceID(root)))

        try await workspace.move(root.appending(path: "api"), to: root.appending(path: "server"))

        #expect(model.tabs == [key("server/index.ts")])
        #expect(model.activeTab == key("server/index.ts"))
    }

    // MARK: - Labels

    @Test func aTabIsCalledAfterItsFile() async throws {
        let (model, _) = await open(["a.txt", "b.txt"])

        #expect(model.openTabs.map(\.name) == ["a.txt", "b.txt"])
        #expect(model.openTabs.allSatisfy { $0.folder == nil })
    }

    /// Two tabs that read the same gain the folder holding them — both of
    /// them, because naming one is no help.
    @Test func tabsWithTheSameNameGainTheirFolder() async throws {
        let (model, registry) = await open(["api/index.ts", "web/index.ts", "a.txt"])

        #expect(model.openTabs.map(\.folder) == ["api", "web", nil])

        await model.close(tab: key("web/index.ts"))
        #expect(model.openTabs.map(\.folder) == [nil, nil])
        _ = registry
    }
}

/// The stored shape, against bytes this build did not write: a fixture encoded
/// by the current types proves nothing, because both sides move together.
@Suite struct EditorUIStateDecodingTests {
    func decoded(_ json: String) throws -> EditorUIState {
        let state = EditorUIState()
        try state.restore(from: Data(json.utf8))
        return state
    }

    /// What the builds that could only open one file at a time wrote.
    @Test func aStoredSingleFileComesBackAsOneTab() throws {
        let state = try decoded(#"{"file":"/code/api/b.txt"}"#)

        #expect(state.files == [PathKey(canonical: "/code/api/b.txt")])
        #expect(state.active == PathKey(canonical: "/code/api/b.txt"))
    }

    @Test func aStoredNothingComesBackEmpty() throws {
        let state = try decoded("{}")

        #expect(state.files.isEmpty)
        #expect(state.active == nil)
    }

    @Test func storedTabsComeBackInOrder() throws {
        let state = try decoded(
            #"{"files":["/code/api/a.txt","/code/api/b.txt"],"active":"/code/api/a.txt"}"#
        )

        #expect(state.files == ["a.txt", "b.txt"].map { PathKey(canonical: "/code/api/" + $0) })
        #expect(state.active == PathKey(canonical: "/code/api/a.txt"))
    }

    /// A build that wrote tabs wins over the legacy field, which it never
    /// writes — so a downgrade and an upgrade do not resurrect an old file.
    @Test func storedTabsWinOverAStoredSingleFile() throws {
        let state = try decoded(#"{"file":"/code/api/old.txt","files":["/code/api/a.txt"],"active":"/code/api/a.txt"}"#)

        #expect(state.files == [PathKey(canonical: "/code/api/a.txt")])
    }

    /// Closing every tab genuinely forgets, rather than leaving the last one
    /// to come back on relaunch.
    @Test func anEmptySetIsWrittenAsAnEmptySet() throws {
        let state = EditorUIState()
        state.files = []
        state.active = nil

        let json = try #require(
            try JSONSerialization.jsonObject(with: try state.encode()) as? [String: Any]
        )

        #expect(json["files"] as? [String] == [])
        #expect(json["active"] == nil)
        #expect(json["file"] == nil)
    }
}
