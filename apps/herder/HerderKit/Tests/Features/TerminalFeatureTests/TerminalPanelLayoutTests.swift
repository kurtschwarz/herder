import Foundation
import Testing

@testable import TerminalFeature

@Suite struct PanelHeightTests {
    let limits = PanelHeight.Limits(defaultHeight: 240, minimumPanel: 120, minimumEditor: 160)

    @Test func neverDraggedTakesTheDefault() {
        #expect(PanelHeight.resolved(nil, in: 800, limits: limits) == 240)
    }

    @Test func aStoredHeightIsKept() {
        #expect(PanelHeight.resolved(300, in: 800, limits: limits) == 300)
    }

    @Test func itIsHeldAboveItsMinimum() {
        #expect(PanelHeight.clamp(40, in: 800, limits: limits) == 120)
    }

    @Test func itLeavesTheEditorItsMinimum() {
        #expect(PanelHeight.clamp(700, in: 800, limits: limits) == 640)
    }

    @Test func aShortWindowGivesThePanelItsMinimumAnyway() {
        #expect(PanelHeight.resolved(300, in: 200, limits: limits) == 120)
    }

    @Test func squeezingDoesNotForgetWhatWasStored() {
        #expect(PanelHeight.resolved(500, in: 400, limits: limits) == 240)
        #expect(PanelHeight.resolved(500, in: 900, limits: limits) == 500)
    }
}
