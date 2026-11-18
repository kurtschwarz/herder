import Core
import Foundation
import Testing

@testable import EditorFeature

/// What the selection prompt tells an agent: which lines, how they are named,
/// and what each action adds.
@Suite struct CodeRefTests {
    static let root = PathKey(canonical: "/code/api")
    static let source = "one\ntwo\nthree\nfour\n"

    private func ref(
        _ file: String = "/code/api/Sources/Foo.swift",
        range: NSRange,
        in text: String = source,
        unsaved: Bool = false
    ) -> CodeRef {
        CodeRef(
            file: PathKey(canonical: file),
            worktree: Self.root,
            selection: SelectedLines(of: range, in: text),
            isUnsaved: unsaved
        )
    }

    // MARK: Lines

    @Test func aCaretIsItsLine() {
        let lines = SelectedLines(of: NSRange(location: 5, length: 0), in: Self.source)
        #expect(lines.lines == 2...2)
        #expect(!lines.isPartial)
        #expect(lines.text == "two\n")
    }

    @Test func wholeLinesAreNotPartial() {
        // "two\nthree\n"
        let lines = SelectedLines(of: NSRange(location: 4, length: 10), in: Self.source)
        #expect(lines.lines == 2...3)
        #expect(!lines.isPartial)
    }

    @Test func aSelectionEndingBeforeTheBreakIsWhole() {
        let lines = SelectedLines(of: NSRange(location: 4, length: 3), in: Self.source)
        #expect(lines.lines == 2...2)
        #expect(!lines.isPartial)
    }

    @Test func startingMidLineIsPartial() {
        let lines = SelectedLines(of: NSRange(location: 5, length: 9), in: Self.source)
        #expect(lines.lines == 2...3)
        #expect(lines.isPartial)
    }

    @Test func endingMidLineIsPartial() {
        let lines = SelectedLines(of: NSRange(location: 0, length: 6), in: Self.source)
        #expect(lines.lines == 1...2)
        #expect(lines.isPartial)
    }

    @Test func aSelectionEndingAtALineStartDoesNotReachIntoIt() {
        let lines = SelectedLines(of: NSRange(location: 0, length: 8), in: Self.source)
        #expect(lines.lines == 1...2)
        #expect(!lines.isPartial)
    }

    @Test func theLastLineWithoutABreakIsWhole() {
        let lines = SelectedLines(of: NSRange(location: 4, length: 3), in: "one\ntwo")
        #expect(lines.lines == 2...2)
        #expect(!lines.isPartial)
        #expect(lines.text == "two")
    }

    // MARK: The ref

    @Test func aPathIsRelativeToTheWorktree() {
        #expect(ref(range: NSRange(location: 4, length: 10)).text == "@Sources/Foo.swift#L2-3")
    }

    @Test func oneLineHasNoRange() {
        #expect(ref(range: NSRange(location: 4, length: 0)).text == "@Sources/Foo.swift#L2")
    }

    @Test func aPathWithASpaceIsQuoted() {
        let text = ref("/code/api/dir name/Foo.swift", range: NSRange(location: 0, length: 8)).text
        #expect(text == "@\"dir name/Foo.swift\"#L1-2")
    }

    @Test func aFileOutsideTheWorktreeKeepsItsAbsolutePath() {
        #expect(ref("/elsewhere/Bar.swift", range: NSRange(location: 0, length: 0)).text == "@/elsewhere/Bar.swift#L1")
    }

    @Test func aFolderNamedLikeTheWorktreeIsNotInsideIt() {
        #expect(ref("/code/api-two/Bar.swift", range: NSRange(location: 0, length: 0)).text == "@/code/api-two/Bar.swift#L1")
    }

    @Test func unsavedTextIsQuotedWithItsLanguage() {
        let text = ref(range: NSRange(location: 4, length: 10), unsaved: true).text
        #expect(text == "Sources/Foo.swift:2-3 (unsaved)\n```swift\ntwo\nthree\n```")
    }

    @Test func theLineRangeIsFirstAndLastJoinedByADash() {
        #expect(ref(range: NSRange(location: 0, length: 19)).text == "@Sources/Foo.swift#L1-4")
    }

    @Test func aSelectionOfOneLineHasNoDashInEitherForm() {
        let caret = NSRange(location: 9, length: 0)
        #expect(ref(range: caret).text == "@Sources/Foo.swift#L3")
        #expect(ref(range: caret, unsaved: true).text == "Sources/Foo.swift:3 (unsaved)\n```swift\nthree\n```")
    }

    @Test func aSelectionEndingAtALineStartKeepsASingleLineRange() {
        // "one\n": the next line is not reached.
        #expect(ref(range: NSRange(location: 0, length: 4)).text == "@Sources/Foo.swift#L1")
    }

    @Test func theLastLineOfAFileWithoutABreakHasNoBlankLineInTheFence() {
        let text = "one\ntwo"
        let ref = ref(range: NSRange(location: 4, length: 3), in: text, unsaved: true)
        #expect(ref.text == "Sources/Foo.swift:2 (unsaved)\n```swift\ntwo\n```")
    }

    @Test func aFileWithNoExtensionHasABareFence() {
        let text = ref("/code/api/Makefile", range: NSRange(location: 0, length: 3), unsaved: true).text
        #expect(text == "Makefile:1 (unsaved)\n```\none\n```")
    }

    @Test func anUntitledBufferIsAlwaysUnsaved() {
        let file = PathKey.untitled("Untitled", in: Self.root)
        let ref = CodeRef(
            file: file,
            worktree: Self.root,
            selection: SelectedLines(of: NSRange(location: 0, length: 3), in: "abc"),
            isUnsaved: false
        )
        #expect(ref.text == "Untitled:1 (unsaved)\n```\nabc\n```")
    }

    @Test func countsItsLines() {
        let ref = ref(range: NSRange(location: 0, length: 14))
        #expect(ref.lineCount == 3)
    }

    // MARK: Messages

    @Test func sendingIsTheRefABlankLineAndTheFeedback() {
        let message = SelectionMessage(.send, ref: ref(range: NSRange(location: 4, length: 3)), feedback: " why?\n")
        #expect(message.text == "@Sources/Foo.swift#L2\n\nwhy?")
        #expect(message.submit)
    }

    @Test func addingToContextDoesNotSubmit() {
        let message = SelectionMessage(.addToContext, ref: ref(range: NSRange(location: 4, length: 3)), feedback: "context")
        #expect(message.text == "@Sources/Foo.swift#L2\n\ncontext")
        #expect(!message.submit)
    }

    @Test(arguments: [
        (SelectionMessage.Action.explain, "Explain what this code does."),
        (.fix, "Find and fix the problem in this code."),
        (.writeTests, "Write tests covering this code."),
    ])
    func aCannedActionAddsItsSentenceBeforeTheFeedback(action: SelectionMessage.Action, sentence: String) {
        let ref = ref(range: NSRange(location: 4, length: 3))

        let bare = SelectionMessage(action, ref: ref, feedback: "")
        #expect(bare.text == "@Sources/Foo.swift#L2\n\n\(sentence)")
        #expect(bare.submit)

        let typed = SelectionMessage(action, ref: ref, feedback: "mind the nil")
        #expect(typed.text == "@Sources/Foo.swift#L2\n\n\(sentence)\nmind the nil")
    }
}
