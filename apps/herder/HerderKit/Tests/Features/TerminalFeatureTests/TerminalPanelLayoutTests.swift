import Foundation
import Testing

@testable import TerminalFeature

@Suite struct HomeRelativePathTests {
    let home = URL(filePath: "/Users/kurt", directoryHint: .isDirectory)

    @Test func theHomeFolderIsATilde() {
        #expect(HomeRelativePath.label(for: home, home: home) == "~")
    }

    @Test func aFolderUnderItIsRelative() {
        #expect(HomeRelativePath.label(for: URL(filePath: "/Users/kurt/dev/app/"), home: home) == "~/dev/app")
    }

    @Test func aFolderOutsideItIsLeftAlone() {
        #expect(HomeRelativePath.label(for: URL(filePath: "/usr/local"), home: home) == "/usr/local")
    }

    @Test func aSiblingWithTheSamePrefixIsNotUnderIt() {
        #expect(HomeRelativePath.label(for: URL(filePath: "/Users/kurtis/dev"), home: home) == "/Users/kurtis/dev")
    }
}

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
