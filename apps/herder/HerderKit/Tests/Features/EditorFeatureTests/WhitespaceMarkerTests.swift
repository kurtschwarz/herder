import Core
import Foundation
import Testing

@testable import EditorFeature

@Suite struct WhitespaceMarkerTests {
    private func find(_ text: String, _ mode: ShowWhitespace, touching range: NSRange? = nil) -> [WhitespaceMarker] {
        let string = text as NSString
        return WhitespaceMarker.find(in: string, touching: range ?? NSRange(location: 0, length: string.length), mode: mode)
    }

    private func marker(_ kind: WhitespaceMarker.Kind, _ location: Int) -> WhitespaceMarker {
        WhitespaceMarker(kind: kind, location: location)
    }

    @Test func noneMarksNothing() {
        #expect(find("a b\t\n", .none).isEmpty)
    }

    @Test func allMarksSpacesTabsAndLineEndings() {
        #expect(find("a b\tc\nd", .all) == [
            marker(.space, 1), marker(.tab, 3), marker(.lineEnding, 5),
        ])
    }

    @Test func aFinalLineWithNoNewlineHasNoLineEnding() {
        #expect(find("a\nb ", .all) == [marker(.lineEnding, 1), marker(.space, 3)])
    }

    @Test func aCRLFEndingIsOneMarkerOnTheCarriageReturn() {
        #expect(find("a\r\nb\r\n", .all) == [marker(.lineEnding, 1), marker(.lineEnding, 4)])
    }

    @Test func trailingMarksOnlyWhatEndsALine() {
        #expect(find("a b \t\nc  \nd e", .trailing) == [
            marker(.space, 3), marker(.tab, 4), marker(.space, 7), marker(.space, 8),
        ])
    }

    @Test func trailingCountsALineOfOnlyWhitespaceAndMarksNoLineEndings() {
        #expect(find("a\n \t\n\nb", .trailing) == [marker(.space, 2), marker(.tab, 3)])
        #expect(find("a\r\n  \r\n", .trailing) == [marker(.space, 3), marker(.space, 4)])
    }

    @Test func trailingMarksTheFinalLineWithNoNewline() {
        #expect(find("a  ", .trailing) == [marker(.space, 1), marker(.space, 2)])
    }

    @Test func aRangeWorksOutWholeLinesSoTrailingStaysRight() {
        // The range ends mid-line, before the whitespace that is trailing.
        #expect(find("ab  \ncd", .trailing, touching: NSRange(location: 0, length: 2)) == [
            marker(.space, 2), marker(.space, 3),
        ])
        #expect(find("a \nb \nc ", .all, touching: NSRange(location: 3, length: 1)) == [
            marker(.space, 4), marker(.lineEnding, 5),
        ])
    }

    @Test func anEmptyTextOrRangeIsFine() {
        #expect(find("", .all).isEmpty)
        #expect(find("a\n", .all, touching: NSRange(location: 2, length: 0)).isEmpty)
    }
}
