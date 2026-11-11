import AppKit
import Testing

@testable import TerminalUI

@Suite struct TerminalPointerShapeTests {
    @Test func aShapeIsTheNearestCursor() {
        let expected: [(TerminalPointerShape, NSCursor)] = [
            (.pointer, .pointingHand),
            (.text, .iBeam),
            (.default, .arrow),
            (.crosshair, .crosshair),
            (.grab, .openHand),
            (.grabbing, .closedHand),
            (.notAllowed, .operationNotAllowed),
            (.ewResize, .resizeLeftRight),
            (.nsResize, .resizeUpDown),
            (.nResize, .resizeUp),
            (.eResize, .resizeRight),
        ]
        for (shape, cursor) in expected {
            let isIt = shape.cursor === cursor
            #expect(isIt, "\(shape)")
        }
    }

    @Test func aShapeWithNoEquivalentIsTheArrow() {
        for shape in [TerminalPointerShape.wait, .zoomIn, .nwseResize, .allScroll] {
            let isArrow = shape.cursor === NSCursor.arrow
            #expect(isArrow, "\(shape)")
        }
    }
}
