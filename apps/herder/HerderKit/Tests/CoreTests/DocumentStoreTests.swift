import Core
import Testing

@Suite @MainActor struct DocumentStoreTests {
    private let store = DocumentStore()
    private let a = PathKey(canonical: "/code/api/a.swift")
    private let b = PathKey(canonical: "/code/api/b.swift")

    // MARK: - Dirtiness

    @Test func aFreshDocumentIsClean() {
        let document = store.open(a, baseline: "let x = 1\n")

        #expect(document.isDirty == false)
        #expect(document.isStale == false)
        #expect(store.dirty.isEmpty)
    }

    @Test func typingMakesItDirtyAndTypingItBackMakesItCleanAgain() {
        let document = store.open(a, baseline: "let x = 1\n")

        document.bufferChanged(to: "let x = 12\n")
        #expect(document.isDirty)
        #expect(store.dirty.count == 1)

        document.bufferChanged(to: "let x = 1\n")
        #expect(document.isDirty == false)
        #expect(store.dirty.isEmpty)
    }

    @Test func openingAgainGivesTheSameDocument() {
        let first = store.open(a, baseline: "one")
        let second = store.open(a, baseline: "two")

        #expect(first === second)
        #expect(second.baseline == "one")
        #expect(store.documents.count == 1)
    }

    @Test func closingForgetsTheDocument() {
        let document = store.open(a, baseline: "")

        #expect(store.close(document) === document)
        #expect(store.documents.isEmpty)
        #expect(store.close(document) == nil)
    }

    // MARK: - Saving

    @Test func savingMakesTheWrittenTextTheBaseline() {
        let document = store.open(a, baseline: "old")
        document.bufferChanged(to: "new")

        document.saved("new", buffer: "new")

        #expect(document.baseline == "new")
        #expect(document.isDirty == false)
    }

    @Test func typingDuringTheWriteLeavesItDirty() {
        let document = store.open(a, baseline: "old")
        document.bufferChanged(to: "new")

        document.saved("new", buffer: "newer")

        #expect(document.baseline == "new")
        #expect(document.isDirty)
    }

    // MARK: - Reading the disk

    @Test func theDiskReturningWhatWasWrittenChangesNothing() {
        let document = store.open(a, baseline: "old")
        document.bufferChanged(to: "new")
        document.saved("new", buffer: "new")

        #expect(document.read("new") == .unchanged)
        #expect(document.isStale == false)
    }

    @Test func aCleanDocumentTakesWhatTheDiskChangedTo() {
        let document = store.open(a, baseline: "old")

        #expect(document.read("outside") == .replace)
        #expect(document.baseline == "outside")
        #expect(document.isDirty == false)
        #expect(document.isStale == false)
    }

    @Test func aDirtyDocumentIsNeverReplacedAndIsMarkedStale() {
        let document = store.open(a, baseline: "old")
        document.bufferChanged(to: "mine")

        #expect(document.read("outside") == .stale)
        #expect(document.baseline == "old")
        #expect(document.isDirty)
        #expect(document.isStale)
    }

    @Test func theDiskGoingBackToTheBaselineClearsStale() {
        let document = store.open(a, baseline: "old")
        document.bufferChanged(to: "mine")
        _ = document.read("outside")

        #expect(document.read("old") == .unchanged)
        #expect(document.isStale == false)
        #expect(document.isDirty)
    }

    @Test func savingOverAStaleDocumentClearsStale() {
        let document = store.open(a, baseline: "old")
        document.bufferChanged(to: "mine")
        _ = document.read("outside")

        document.saved("mine", buffer: "mine")

        #expect(document.isStale == false)
        #expect(document.isDirty == false)
    }

    // MARK: - Moving

    @Test func aRenameKeepsTheDocumentAndItsUnsavedText() {
        let document = store.open(a, baseline: "old")
        document.bufferChanged(to: "mine")
        let buffer = document.buffer

        let move = store.move(from: a, to: b)

        #expect(move.moved.count == 1)
        #expect(move.collapsed.isEmpty)
        #expect(document.key == b)
        #expect(document.buffer == buffer)
        #expect(document.isDirty)
        #expect(store.documents(at: a).isEmpty)
    }

    @Test func aFolderRenameCarriesWhatIsInsideIt() {
        let inside = store.open(PathKey(canonical: "/code/api/src/a.swift"), baseline: "")
        let beside = store.open(b, baseline: "")

        store.move(from: PathKey(canonical: "/code/api/src"), to: PathKey(canonical: "/code/api/lib"))

        #expect(inside.key == PathKey(canonical: "/code/api/lib/a.swift"))
        #expect(beside.key == b)
    }

    @Test func aMoveOntoACleanDocumentCollapsesIt() {
        let moving = store.open(a, baseline: "one")
        let displaced = store.open(b, baseline: "two")

        let move = store.move(from: a, to: b)

        #expect(move.collapsed.count == 1)
        #expect(move.collapsed.first === displaced)
        #expect(store.documents.count == 1)
        #expect(store.documents.first === moving)
        #expect(moving.key == b)
    }

    @Test func aMoveOntoADirtyDocumentKeepsBoth() {
        let moving = store.open(a, baseline: "one")
        let displaced = store.open(b, baseline: "two")
        displaced.bufferChanged(to: "mine")

        let move = store.move(from: a, to: b)

        #expect(move.collapsed.isEmpty)
        #expect(store.documents.count == 2)
        #expect(store.documents(at: b).count == 2)
        #expect(moving.key == b)
        #expect(displaced.isDirty)
    }

    @Test func theDisplacedDirtyDocumentFindsItselfStaleOnTheNextRead() {
        store.open(a, baseline: "one")
        let displaced = store.open(b, baseline: "two")
        displaced.bufferChanged(to: "mine")
        store.move(from: a, to: b)

        #expect(displaced.read("one") == .stale)
        #expect(displaced.isStale)
    }
}
