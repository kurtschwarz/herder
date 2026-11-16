import Core
import Foundation
import Testing

@testable import EditorFeature

@Suite struct TextEditTests {
    private func token(_ location: Int, _ length: Int, _ kind: SyntaxTokenKind = .string) -> SyntaxToken {
        SyntaxToken(range: NSRange(location: location, length: length), kind: kind)
    }

    private func edit(at location: Int, removing removed: Int = 0, adding added: Int = 0) -> TextEdit {
        TextEdit(replaced: NSRange(location: location, length: removed), length: added)
    }

    @Test func tokensBeforeTheEditAreLeftAlone() {
        let tokens = [token(0, 3)]
        #expect(tokens.applying(edit(at: 10, adding: 2)) == tokens)
    }

    @Test func tokensAfterTheEditMoveByTheChangeInLength() {
        #expect([token(10, 3)].applying(edit(at: 2, adding: 4)) == [token(14, 3)])
        #expect([token(10, 3)].applying(edit(at: 2, removing: 5)) == [token(5, 3)])
    }

    @Test func typingInsideATokenGrowsIt() {
        #expect([token(4, 8)].applying(edit(at: 6, adding: 1)) == [token(4, 9)])
    }

    @Test func typingAtAnEdgeDoesNotGrowTheToken() {
        let tokens = [token(4, 8)]
        #expect(tokens.applying(edit(at: 4, adding: 1)) == [token(5, 8)])
        #expect(tokens.applying(edit(at: 12, adding: 1)) == [token(4, 8)])
    }

    @Test func deletingInsideATokenShrinksIt() {
        #expect([token(4, 8)].applying(edit(at: 6, removing: 2)) == [token(4, 6)])
    }

    @Test func deletingAWholeTokenRemovesIt() {
        #expect([token(4, 3), token(10, 2)].applying(edit(at: 4, removing: 3)) == [token(7, 2)])
        #expect([token(4, 3)].applying(edit(at: 2, removing: 8)).isEmpty)
    }

    @Test func deletingAcrossAnEdgeKeepsTheRest() {
        #expect([token(4, 8)].applying(edit(at: 2, removing: 4)) == [token(2, 6)])
        #expect([token(4, 8)].applying(edit(at: 10, removing: 5)) == [token(4, 6)])
    }

    @Test func replacingAcrossTwoTokensKeepsTheOutsideOfEach() {
        let tokens = [token(0, 5, .keyword), token(6, 5, .string)]
        let result = tokens.applying(edit(at: 3, removing: 6, adding: 1))
        #expect(result == [token(0, 3, .keyword), token(4, 2, .string)])
    }

    @Test func identicalRunsNeedNoRepaint() {
        let tokens = [token(0, 3), token(5, 2)]
        #expect(tokens.changedRange(to: tokens) == nil)
        #expect([SyntaxToken]().changedRange(to: []) == nil)
    }

    @Test func onlyTheTokenThatChangedIsRepainted() {
        let old = [token(0, 3, .keyword), token(4, 5, .string), token(10, 2, .number)]
        let new = [token(0, 3, .keyword), token(4, 5, .type), token(10, 2, .number)]
        #expect(old.changedRange(to: new) == NSRange(location: 4, length: 5))
    }

    @Test func anAddedTokenIsRepaintedAlone() {
        let old = [token(0, 3), token(10, 2)]
        let new = [token(0, 3), token(5, 3), token(10, 2)]
        #expect(old.changedRange(to: new) == NSRange(location: 5, length: 3))
    }

    @Test func aRemovedTokenIsClearedWhereItWas() {
        let old = [token(0, 3), token(5, 3), token(10, 2)]
        let new = [token(0, 3), token(10, 2)]
        #expect(old.changedRange(to: new) == NSRange(location: 5, length: 3))
    }

    @Test func everythingFromAnOpenedStringOnwardIsRepainted() {
        let old = [token(0, 3, .keyword), token(10, 3, .keyword), token(20, 3, .keyword)]
        let new = [token(0, 3, .keyword), token(8, 20, .string)]
        #expect(old.changedRange(to: new) == NSRange(location: 8, length: 20))
    }

    @Test func coloursAppearingOnPlainTextCoverTheWholeRun() {
        let new = [token(2, 3), token(10, 4)]
        #expect([SyntaxToken]().changedRange(to: new) == NSRange(location: 2, length: 12))
    }

    @Test func aRangeFollowsAnEditBeforeIt() {
        let edit = TextEdit(replaced: NSRange(location: 0, length: 0), length: 3)
        #expect(edit.carrying(NSRange(location: 10, length: 4)) == NSRange(location: 13, length: 4))
    }

    @Test func aRangeCutByADeleteLosesWhatWasCut() {
        let edit = TextEdit(replaced: NSRange(location: 4, length: 4), length: 0)
        #expect(edit.carrying(NSRange(location: 2, length: 4)) == NSRange(location: 2, length: 2))
        #expect(edit.carrying(NSRange(location: 6, length: 6)) == NSRange(location: 4, length: 4))
    }

    @Test func aRangeAroundAnInsertGrowsWithIt() {
        let edit = TextEdit(replaced: NSRange(location: 5, length: 0), length: 2)
        #expect(edit.carrying(NSRange(location: 2, length: 8)) == NSRange(location: 2, length: 10))
    }

    @Test func replacingInsideATokenKeepsItWhole() {
        #expect([token(4, 8)].applying(edit(at: 6, removing: 2, adding: 5)) == [token(4, 11)])
    }
}
