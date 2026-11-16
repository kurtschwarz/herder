import Foundation
import Testing

@testable import EditorFeature

@Suite struct LineChangesTests {
    func changes(_ base: String, _ current: String) -> LineChanges {
        LineChanges(base: base, current: current)
    }

    // MARK: - Nothing changed

    @Test func identicalTextHasNoChanges() {
        #expect(changes("a\nb\nc\n", "a\nb\nc\n") == .none)
    }

    @Test func aTrailingNewlineIsNotALine() {
        #expect(changes("a\nb\n", "a\nb\nc\n").added == IndexSet(integer: 3))
        #expect(changes("a\nb", "a\nb\n") == .none)
    }

    // MARK: - Added

    @Test func linesInsertedAtTheStartAreAdded() {
        let result = changes("b\nc\n", "x\ny\nb\nc\n")

        #expect(result.added == IndexSet(1...2))
        #expect(result.modified.isEmpty)
        #expect(result.deleted.isEmpty)
    }

    @Test func linesInsertedInTheMiddleAreAdded() {
        #expect(changes("a\nc\n", "a\nb\nc\n").added == IndexSet(integer: 2))
    }

    @Test func linesInsertedAtTheEndAreAdded() {
        #expect(changes("a\nb\n", "a\nb\nc\nd\n").added == IndexSet(3...4))
    }

    @Test func everyLineIsAddedWhenTheBaseIsEmpty() {
        let result = changes("", "a\nb\nc\n")

        #expect(result.added == IndexSet(1...3))
        #expect(result.modified.isEmpty)
        #expect(result.deleted.isEmpty)
    }

    // MARK: - Deleted

    @Test func linesRemovedFromTheStartMarkTheTop() {
        let result = changes("x\ny\nb\n", "b\n")

        #expect(result.deleted == [0])
        #expect(result.added.isEmpty)
        #expect(result.modified.isEmpty)
    }

    @Test func linesRemovedFromTheMiddleMarkTheBoundaryAfterTheLineBefore() {
        #expect(changes("a\nb\nc\n", "a\nc\n").deleted == [1])
    }

    @Test func linesRemovedFromTheEndMarkTheBottom() {
        #expect(changes("a\nb\nc\n", "a\nb\n").deleted == [2])
    }

    @Test func removingEverythingMarksTheTop() {
        #expect(changes("a\nb\n", "").deleted == [0])
    }

    // MARK: - Modified

    @Test func aRewrittenLineIsModified() {
        let result = changes("a\nb\nc\n", "a\nB\nc\n")

        #expect(result.modified == IndexSet(integer: 2))
        #expect(result.added.isEmpty)
        #expect(result.deleted.isEmpty)
    }

    @Test func aRewrittenFirstAndLastLineAreModified() {
        #expect(changes("a\nb\nc\n", "A\nb\nC\n").modified == IndexSet([1, 3]))
    }

    @Test func moreLinesInsertedThanRemovedAreAllModified() {
        let result = changes("a\nb\nc\n", "a\nX\nY\nZ\nc\n")

        #expect(result.modified == IndexSet(2...4))
        #expect(result.added.isEmpty)
    }

    @Test func moreLinesRemovedThanInsertedAreModifiedWithNoDeletedMarker() {
        let result = changes("a\nb\nc\nd\n", "a\nX\nd\n")

        #expect(result.modified == IndexSet(integer: 2))
        #expect(result.deleted.isEmpty)
    }

    @Test func whitespaceOnlyChangesCount() {
        #expect(changes("a\nb\n", "a\nb \n").modified == IndexSet(integer: 2))
    }

    @Test func lineEndingsAreNotMistakenForContent() {
        #expect(changes("a\r\nb\r\n", "a\r\nb\r\nc\r\n").added == IndexSet(integer: 3))
    }

    // MARK: - Several hunks

    @Test func eachHunkIsSortedOnItsOwn() {
        let result = changes("a\nb\nc\nd\ne\n", "a\nB\nc\nd\ne\nf\n")

        #expect(result.modified == IndexSet(integer: 2))
        #expect(result.added == IndexSet(integer: 6))

        let mixed = changes("a\nb\nc\nd\n", "a\nc\nd\nnew\n")
        #expect(mixed.deleted == [1])
        #expect(mixed.added == IndexSet(integer: 4))
    }

    // MARK: - Too big to diff

    @Test func aFileWithTooManyLinesHasNoChanges() {
        let base = String(repeating: "a\n", count: LineChanges.maxLines + 1)

        #expect(LineChanges(base: base, current: base + "b\n") == .none)
    }

    @Test func aFileOverTheSizeLimitHasNoChanges() {
        let long = String(repeating: "a", count: LineChanges.maxBytes + 1)

        #expect(LineChanges(base: "x\n", current: long) == .none)
    }
}
