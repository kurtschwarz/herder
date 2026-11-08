import CoreGraphics
import Testing

@testable import TerminalUI

@Suite struct BlockElementTests {
    func rects(_ text: String) -> [CGRect]? {
        BlockElement(text)?.parts.map(\.rect)
    }

    @Test func theUpperHalfIsTheTopOfTheCell() {
        #expect(rects("▀") == [CGRect(x: 0, y: 0, width: 1, height: 0.5)])
    }

    @Test func eighthsGrowFromTheirEdge() {
        #expect(rects("▁") == [CGRect(x: 0, y: 7.0 / 8, width: 1, height: 1.0 / 8)])
        #expect(rects("█") == [CGRect(x: 0, y: 0, width: 1, height: 1)])
        #expect(rects("▉") == [CGRect(x: 0, y: 0, width: 7.0 / 8, height: 1)])
        #expect(rects("▏") == [CGRect(x: 0, y: 0, width: 1.0 / 8, height: 1)])
    }

    @Test func quadrantsAreQuarters() {
        #expect(rects("▚") == [CGRect(x: 0, y: 0, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)])
        #expect(rects("▟")?.count == 3)
    }

    @Test func shadesFillTheCellFaintly() {
        #expect(BlockElement("▒")?.parts.map(\.opacity) == [0.5])
    }

    @Test func anythingElseIsTheFonts() {
        #expect(BlockElement("a") == nil)
        #expect(BlockElement("┃") == nil)
        #expect(BlockElement("▀▀") == nil)
    }
}
