import Core
import Foundation
import Services
import TestSupport
import Testing

@testable import EditorFeature

/// A highlighter that does not answer until told to, so a test can look at the
/// pane while the parser is still working.
///
/// `@unchecked Sendable` and plainly mutable: these tests are single-threaded,
/// and the alternative is a lock whose only job is to satisfy the compiler.
final class SlowSyntaxHighlighter: SyntaxHighlighter, @unchecked Sendable {
    private var byText: [String: [SyntaxToken]] = [:]
    private var anyText: [SyntaxToken]?

    /// Answers whatever is asked with `tokens`.
    func finish(with tokens: [SyntaxToken]) { anyText = tokens }

    /// Answers only calls about `contents`, so a test can let one call through
    /// while another stays waiting. Needed to tell a stale answer from a
    /// current one: a fake that answers everything the same way cannot.
    func finish(_ contents: String, with tokens: [SyntaxToken]) { byText[contents] = tokens }

    /// Makes every call wait again.
    func hold() {
        anyText = nil
        byText = [:]
    }

    /// Bounded, so a call left waiting when a test ends stops spinning rather
    /// than outliving it.
    func tokens(in contents: String, ofFileNamed fileName: String) async -> [SyntaxToken] {
        for _ in 0..<10_000 {
            if let tokens = byText[contents] ?? anyText { return tokens }
            await Task.yield()
        }
        return []
    }
}

@Suite struct EditorModelTests {
    let files = InMemoryFileClient()
    let git = StubGitClient()
    let watcher = StubFileWatcherClient()
    let clock = VirtualClockClient()
    let store: WorkspaceRegistry
    let model: EditorModel
    let root = URL(filePath: "/code/api")

    init() {
        store = WorkspaceRegistry(files: files, git: git, watcher: watcher, clock: clock)
        model = EditorModel(store: store, files: files, highlighter: TreeSitterHighlighter())
    }

    func file(_ name: String) -> DirectoryEntry {
        DirectoryEntry(url: root.appending(path: name), isDirectory: false)
    }

    func path(_ name: String) -> String {
        root.appending(path: name).path(percentEncoded: false)
    }

    /// Selects `root` with `names` in it, each holding its own name as text.
    func start(with names: [String]) async throws -> Workspace {
        for name in names { files.seed(path(name), "contents of \(name)") }
        files.seed(children: names.map(file), of: root)
        let state = try #require(await store.select(root))
        await state.refresh()
        return state
    }

    func settle() async {
        for _ in 0..<500 { await Task.yield() }
    }

    /// What the pane shows for a file with nothing to highlight in it. These
    /// suites use `.txt`, which no grammar claims, so the real highlighter
    /// finds nothing and the text is all there is to assert on.
    func plain(_ text: String) -> EditorModel.Content {
        .text(SourceText(text: text))
    }

    @Test func openingAFileShowsItsText() async throws {
        _ = try await start(with: ["a.txt"])

        await model.open(root.appending(path: "a.txt"))

        #expect(model.content == plain("contents of a.txt"))
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

        #expect(model.content == plain("rewritten"))
    }

    @Test func aFileThatGoesStaysOpenAndIsMarkedDeleted() async throws {
        _ = try await start(with: ["a.txt"])
        await model.open(root.appending(path: "a.txt"))

        files.seed(children: [], of: root)
        watcher.change([root])
        await settle()

        #expect(model.isDeleted)
        #expect(model.content == plain("contents of a.txt"))
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
        #expect(model.content == plain("regenerated"))
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

    /// The whole chain in one assertion: a file the explorer clicked, read
    /// through the file client, parsed by the crate, published as one value.
    @Test func openingASourceFileShowsItHighlighted() async throws {
        _ = try await start(with: ["A.swift"])
        files.seed(path("A.swift"), "// a note\nlet x = 1\n")

        await model.open(root.appending(path: "A.swift"))

        let content = try #require(model.content)
        guard case .text(let source) = content else {
            Issue.record("expected text, got \(content)")
            return
        }
        #expect(source.text == "// a note\nlet x = 1\n")
        #expect(source.tokens.contains { $0.kind == .comment })
        #expect(source.tokens.contains { $0.kind == .keyword })
    }

    /// The text is on screen before the highlighter has run, so a slow grammar
    /// never sits between a click and the file appearing. Compiling one
    /// language's queries takes up to a quarter of a second, so this is the
    /// difference between instant and visibly late.
    @Test func theTextIsShownBeforeItIsColoured() async throws {
        let slow = SlowSyntaxHighlighter()
        let model = EditorModel(store: store, files: files, highlighter: slow)
        _ = try await start(with: ["A.swift"])
        files.seed(path("A.swift"), "let x = 1\n")

        // Not awaited: `open` returns once the file is coloured, and the point
        // here is what the pane shows before that.
        let opening = Task { await model.open(root.appending(path: "A.swift")) }
        await settle()

        #expect(model.content == plain("let x = 1\n"))

        slow.finish(with: [SyntaxToken(range: NSRange(location: 0, length: 3), kind: .keyword)])
        await opening.value

        guard case .text(let source) = try #require(model.content) else {
            Issue.record("expected text")
            return
        }
        #expect(source.text == "let x = 1\n")
        #expect(source.tokens.map(\.kind) == [.keyword])
    }

    /// A worktree tells every observer when any folder in it is read, so
    /// expanding a folder in the explorer reloads the open file even though
    /// nothing about it changed. The reload must leave the pane alone: before
    /// this was guarded, the colour dropped out and came back on every click of
    /// a disclosure triangle.
    @Test func aReloadThatFindsTheSameTextKeepsTheColourAlreadyShown() async throws {
        let slow = SlowSyntaxHighlighter()
        let model = EditorModel(store: store, files: files, highlighter: slow)
        let state = try await start(with: ["A.swift", "sub"])
        files.seed(path("A.swift"), "let x = 1\n")
        slow.finish(with: [SyntaxToken(range: NSRange(location: 0, length: 3), kind: .keyword)])
        await model.open(root.appending(path: "A.swift"))
        let coloured = model.content

        // Held, so a highlight the reload started could not have finished yet.
        // If the colour is still there, the reload never took it away.
        slow.hold()
        await state.open(PathKey(canonical: path("sub")))
        await settle()

        #expect(model.content == coloured)
        guard case .text(let source) = try #require(model.content) else {
            Issue.record("expected text")
            return
        }
        #expect(!source.tokens.isEmpty)
    }

    @Test func aReloadThatFindsNewTextStillRecolours() async throws {
        _ = try await start(with: ["A.swift"])
        files.seed(path("A.swift"), "let x = 1\n")
        await model.open(root.appending(path: "A.swift"))

        files.seed(path("A.swift"), "// note\nstruct B {}\n")
        watcher.change([root])
        await settle()

        guard case .text(let source) = try #require(model.content) else {
            Issue.record("expected text")
            return
        }
        #expect(source.text == "// note\nstruct B {}\n")
        #expect(source.tokens.contains { $0.kind == .comment })
    }

    /// The invariant that lets colour arrive separately: tokens are applied only
    /// to the exact string they were found in. Here the file is rewritten while
    /// the highlighter is still working on the old text, so those tokens must be
    /// dropped rather than painted onto the new text.
    @Test func tokensForTextThatIsNoLongerShownAreDropped() async throws {
        let slow = SlowSyntaxHighlighter()
        let model = EditorModel(store: store, files: files, highlighter: slow)
        _ = try await start(with: ["A.swift"])
        let old = "let verylongname = 1\n"
        files.seed(path("A.swift"), old)
        let opening = Task { await model.open(root.appending(path: "A.swift")) }
        await settle()

        files.seed(path("A.swift"), "x\n")
        watcher.change([root])
        await settle()

        // Only the call about the old text is allowed to answer. Its range was
        // valid then and runs past the end of what is on screen now: painting
        // it would throw, so dropping it is the only safe answer.
        slow.finish(old, with: [SyntaxToken(range: NSRange(location: 4, length: 12), kind: .variable)])
        await opening.value
        await settle()

        #expect(model.content == plain("x\n"))
    }

    /// Text and tokens are one value, so there is no state in which colour is
    /// applied to a string it was not computed for.
    @Test func tokensNeverOutliveTheTextTheyWereFoundIn() async throws {
        _ = try await start(with: ["A.swift"])
        files.seed(path("A.swift"), "// a note\nlet x = 1\n")
        await model.open(root.appending(path: "A.swift"))

        files.seed(path("A.swift"), "let y = 2\n")
        watcher.change([root])
        await settle()

        let content = try #require(model.content)
        guard case .text(let source) = content else {
            Issue.record("expected text, got \(content)")
            return
        }
        #expect(source.text == "let y = 2\n")
        for token in source.tokens {
            #expect(NSMaxRange(token.range) <= (source.text as NSString).length)
        }
    }

    @Test func aHighlighterThatFindsNothingStillShowsTheText() async throws {
        let plainModel = EditorModel(store: store, files: files, highlighter: NoSyntaxHighlighter())
        _ = try await start(with: ["A.swift"])
        files.seed(path("A.swift"), "let x = 1\n")

        await plainModel.open(root.appending(path: "A.swift"))

        #expect(plainModel.content == plain("let x = 1\n"))
    }

    @Test func openingTheOpenFileAgainKeepsTheSession() async throws {
        _ = try await start(with: ["a.txt"])
        await model.open(root.appending(path: "a.txt"))
        let session = model.session

        await model.open(root.appending(path: "a.txt"))

        #expect(model.session == session)
    }
}
