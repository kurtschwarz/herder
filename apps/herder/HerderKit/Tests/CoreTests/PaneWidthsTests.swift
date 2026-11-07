import Foundation
import Testing

@testable import Core

@Suite struct PaneWidthsTests {
    private let limits = PaneWidths.Limits(defaultWidth: 236, minimumPane: 180, minimumEditor: 400)

    @Test func aPaneNeverDraggedTakesTheDefault() {
        let widths = PaneWidths().resolved(in: 1000, limits: limits)

        #expect(widths.leading == 236)
        #expect(widths.trailing == 236)
    }

    @Test func storedWidthsAreUsedWhenTheyFit() {
        let widths = PaneWidths(leading: 300, trailing: 250).resolved(in: 1000, limits: limits)

        #expect(widths.leading == 300)
        #expect(widths.trailing == 250)
    }

    @Test func aStoredWidthBelowTheMinimumIsRaisedToIt() {
        let widths = PaneWidths(leading: 50, trailing: 10).resolved(in: 1000, limits: limits)

        #expect(widths.leading == 180)
        #expect(widths.trailing == 180)
    }

    @Test func aTightWindowTakesFromBothPanesInProportion() {
        // 900 shared, 400 kept for the editor: 500 for panes, 140 above the
        // two minimums. Stored: 280 above (100 + 180), so half is kept.
        let widths = PaneWidths(leading: 280, trailing: 360).resolved(in: 900, limits: limits)

        #expect(widths.leading == 230)
        #expect(widths.trailing == 270)
        #expect(widths.leading + widths.trailing == 500)
    }

    @Test func noPaneGoesBelowItsMinimumWhenTheWindowIsTiny() {
        let widths = PaneWidths(leading: 400, trailing: 400).resolved(in: 500, limits: limits)

        #expect(widths.leading == 180)
        #expect(widths.trailing == 180)
    }

    @Test func squeezingDoesNotChangeWhatIsStored() {
        let stored = PaneWidths(leading: 400, trailing: 400)
        _ = stored.resolved(in: 900, limits: limits)

        #expect(stored.resolved(in: 2000, limits: limits).leading == 400)
    }

    @Test func aDragIsHeldToTheMinimum() {
        let widths = PaneWidths().setting(.leading, to: 20, in: 1000, limits: limits)

        #expect(widths.leading == 180)
        #expect(widths.trailing == nil)
    }

    @Test func aDragIsHeldToWhatTheOtherPaneLeavesTheEditor() {
        // 1000 - 400 for the editor - 236 for the other pane.
        let widths = PaneWidths().setting(.trailing, to: 900, in: 1000, limits: limits)

        #expect(widths.trailing == 364)
    }

    @Test func aDragWithinBoundsIsTakenAsProposed() {
        let widths = PaneWidths().setting(.leading, to: 300, in: 1000, limits: limits)

        #expect(widths.leading == 300)
    }

    @Test func aDragAgainstAnAlreadySqueezedPaneUsesWhatIsDrawn() {
        // The stored trailing width is 500 but only 270 is drawn at 900.
        let stored = PaneWidths(leading: 280, trailing: 500)
        let drawn = stored.resolved(in: 900, limits: limits)
        let widths = stored.setting(.leading, to: 900, in: 900, limits: limits)

        #expect(widths.leading == 900 - 400 - drawn.trailing)
    }

    @Test func resettingReturnsOnlyThatPaneToTheDefault() {
        let widths = PaneWidths(leading: 300, trailing: 250).resetting(.leading)

        #expect(widths.leading == nil)
        #expect(widths.trailing == 250)
    }

    @Test func anOldBlobWithNoWidthsDecodesToNone() throws {
        let widths = try JSONDecoder().decode(PaneWidths.self, from: Data("{}".utf8))

        #expect(widths == PaneWidths())
    }

    // MARK: - The agent panel

    @Test func anAgentPanelNeverDraggedTakesTheDefault() {
        #expect(PaneWidths().resolvedAgent(in: 1400, limits: limits) == 236)
    }

    @Test func theAgentPanelLeavesTheOuterPanesAndTheEditorTheirMinimums() {
        // 1000 shared: 400 for the editor and 360 for two minimum panes leave 240.
        #expect(PaneWidths(agent: 600).resolvedAgent(in: 1000, limits: limits) == 240)
    }

    @Test func theAgentPanelIsNeverNarrowerThanAPane() {
        #expect(PaneWidths(agent: 20).resolvedAgent(in: 1400, limits: limits) == 180)
        #expect(PaneWidths().resolvedAgent(in: 500, limits: limits) == 180)
    }

    @Test func draggingTheAgentPanelIsHeldToTheRoom() {
        let widths = PaneWidths().settingAgent(to: 900, in: 1000, limits: limits)

        #expect(widths.agent == 240)
        #expect(widths.settingAgent(to: 10, in: 1000, limits: limits).agent == 180)
    }

    @Test func resettingTheAgentPanelLeavesTheOtherPanesAlone() {
        let widths = PaneWidths(leading: 300, trailing: 250, agent: 400).resettingAgent()

        #expect(widths == PaneWidths(leading: 300, trailing: 250))
    }

    @Test func theAgentWidthSurvivesTheRoundTripAndAnOldFileHasNone() throws {
        let widths = PaneWidths(leading: 300, agent: 320)
        let decoded = try JSONDecoder().decode(PaneWidths.self, from: JSONEncoder().encode(widths))
        #expect(decoded == widths)

        let old = try JSONDecoder().decode(PaneWidths.self, from: Data(#"{"leading":300}"#.utf8))
        #expect(old == PaneWidths(leading: 300))
    }
}
