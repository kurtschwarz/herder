import Foundation
import Testing

@testable import Core

/// Where a dragged tab would land, and what the others do to make room. Tabs
/// are `a` 100 wide, `b` 60, `c` 140, with 4 between: they start at 0, 104 and
/// 168, and their middles are at 50, 134 and 238.
@Suite struct TabDragStateTests {
    let a = "a"
    let b = "b"
    let c = "c"

    func drag(_ key: String, by translation: CGFloat, within run: ClosedRange<Int>? = nil) throws -> TabDragState<String> {
        var state = try #require(
            TabDragState(dragging: key, in: [a, b, c], widths: [a: 100, b: 60, c: 140], spacing: 4, within: run)
        )
        state.translation = translation
        return state
    }

    @Test func aTabThatHasNotMovedStays() throws {
        let state = try drag(b, by: 0)

        #expect(state.targetIndex == 1)
        #expect(state.offset(for: a) == 0)
        #expect(state.offset(for: c) == 0)
    }

    /// `a`'s middle is at 50 and `b`'s at 134: crossing it takes more than 84.
    @Test func aTabMustCrossTheMiddleOfItsNeighbour() throws {
        #expect(try drag(b, by: -83).targetIndex == 1)
        #expect(try drag(b, by: -85).targetIndex == 0)
    }

    /// Variable widths: `c`'s middle is at 238, so `b` has to go past 104.
    @Test func widthsDecideWhereTheMiddlesAre() throws {
        #expect(try drag(b, by: 103).targetIndex == 1)
        #expect(try drag(b, by: 105).targetIndex == 2)
    }

    @Test func aLongDragCrossesSeveralTabs() throws {
        #expect(try drag(a, by: 500).targetIndex == 2)
        #expect(try drag(c, by: -500).targetIndex == 0)
    }

    @Test func neighboursMakeRoomForTheWidthOfTheTabInHand() throws {
        let state = try drag(a, by: 150)

        #expect(state.targetIndex == 1)
        #expect(state.offset(for: b) == -104)
        #expect(state.offset(for: c) == 0)
    }

    @Test func neighboursOnTheOtherSideShiftTheOtherWay() throws {
        let state = try drag(c, by: -200)

        #expect(state.targetIndex == 0)
        #expect(state.offset(for: a) == 144)
        #expect(state.offset(for: b) == 144)
    }

    @Test func theTabInHandCannotBePulledOffEitherEnd() throws {
        #expect(try drag(b, by: -900).offset(for: b) == -104)
        #expect(try drag(b, by: 900).offset(for: b) == 168 + 140 - 104 - 60)
        #expect(try drag(b, by: 30).offset(for: b) == 30)
    }

    @Test func aTabWithNoPlaceInTheStripIsNotDragged() {
        #expect(TabDragState(dragging: "z", in: [a, b, c], widths: [:], spacing: 4) == nil)
    }

    /// `a` pinned: `b` and `c` may only trade places with each other.
    @Test func aTabStaysInItsRun() throws {
        #expect(try drag(b, by: -500, within: 1...2).targetIndex == 1)
        #expect(try drag(b, by: -500, within: 1...2).offset(for: b) == 0)
        #expect(try drag(b, by: -500, within: 1...2).offset(for: a) == 0)
        #expect(try drag(b, by: 500, within: 1...2).targetIndex == 2)
        #expect(try drag(a, by: 500, within: 0...0).targetIndex == 0)
        #expect(try drag(a, by: 500, within: 0...0).offset(for: a) == 0)
    }

    @Test func theEdgesScrollTowardsTheNextSlot() throws {
        let state = try drag(b, by: 0)

        let left = try #require(state.edgeScrollTarget(pointerX: 10, viewport: 400))
        #expect(left.id == a)
        #expect(left.leading)

        let right = try #require(state.edgeScrollTarget(pointerX: 390, viewport: 400))
        #expect(right.id == c)
        #expect(!right.leading)

        #expect(state.edgeScrollTarget(pointerX: 200, viewport: 400) == nil)
    }
}
