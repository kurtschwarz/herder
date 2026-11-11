import DesignSystem
import Foundation
import Testing

@testable import TerminalUI

/// Against the real libghostty-vt, because what is worth testing is what it
/// makes of known bytes and that we read it back correctly. Nothing here looks
/// at pixels.
@Suite struct TerminalEmulatorTests {
    let esc = "\u{1b}"

    func emulator(columns: Int = 20, rows: Int = 5) -> TerminalEmulator {
        TerminalEmulator(columns: columns, rows: rows, scrollbackLines: 100)
    }

    func feed(_ emulator: TerminalEmulator, _ text: String) {
        emulator.write(Data(text.utf8))
        emulator.update()
    }

    func line(_ emulator: TerminalEmulator, _ row: Int) -> String {
        emulator.cells[row].map { $0.text.isEmpty ? " " : $0.text }.joined()
            .replacing(/\s+$/, with: "")
    }

    // MARK: Screen

    @Test func textLandsInTheGrid() {
        let terminal = emulator()
        feed(terminal, "hello\r\nworld")
        #expect(line(terminal, 0) == "hello")
        #expect(line(terminal, 1) == "world")
        #expect(line(terminal, 2) == "")
    }

    @Test func aWideCharacterIsOneCluster() {
        let terminal = emulator()
        feed(terminal, "a日b")
        #expect(terminal.cells[0][0].text == "a")
        #expect(terminal.cells[0][1].text == "日")
    }

    @Test func aCombiningMarkStaysWithItsBase() {
        let terminal = emulator()
        feed(terminal, "e\u{301}x")
        #expect(terminal.cells[0][0].text == "e\u{301}")
        #expect(terminal.cells[0][1].text == "x")
    }

    @Test func theCursorFollowsTheText() {
        let terminal = emulator()
        feed(terminal, "ab\r\nc")
        #expect(terminal.cursor == TerminalEmulator.Cursor(column: 1, row: 1, style: .block))
    }

    @Test func aHiddenCursorIsNone() {
        let terminal = emulator()
        feed(terminal, "\(esc)[?25l")
        #expect(terminal.cursor == nil)
    }

    @Test func anUpdateReportsOnlyTheRowsThatChanged() {
        let terminal = emulator()
        feed(terminal, "one\r\ntwo\r\nthree")
        _ = terminal.update()

        terminal.write(Data("\(esc)[3;1HX".utf8))
        let changed = terminal.update()
        #expect(changed.contains(2))
        #expect(!changed.contains(0))
        #expect(!changed.contains(1))
        #expect(line(terminal, 2) == "Xhree")
    }

    @Test func aQuietTerminalChangesNothing() {
        let terminal = emulator()
        feed(terminal, "x")
        #expect(terminal.update().isEmpty)
    }

    @Test func resizingRebuildsEveryRow() {
        let terminal = emulator()
        feed(terminal, "hello")
        terminal.resize(columns: 30, rows: 8, cellWidth: 8, cellHeight: 16)
        let changed = terminal.update()
        #expect(changed == Set(0..<8))
        #expect(terminal.cells.count == 8)
        #expect(terminal.cells[0].count == 30)
        #expect(line(terminal, 0) == "hello")
    }

    // MARK: Colour

    @Test func aPaletteColourIsTheThemes() {
        let terminal = emulator()
        feed(terminal, "\(esc)[31mr")
        #expect(terminal.cells[0][0].foreground == Theme.Terminal.ansi[1])
    }

    @Test func aBrightColourIsTheThemesBrightOne() {
        let terminal = emulator()
        feed(terminal, "\(esc)[92mg")
        #expect(terminal.cells[0][0].foreground == Theme.Terminal.ansi[10])
    }

    @Test func the256ColourCubeIsTheUsualOne() {
        let terminal = emulator()
        feed(terminal, "\(esc)[38;5;196mr\(esc)[38;5;244mg")
        #expect(terminal.cells[0][0].foreground == Theme.Terminal.RGB(0xff0000))
        #expect(terminal.cells[0][1].foreground == Theme.Terminal.RGB(0x808080))
    }

    @Test func trueColourIsExactlyWhatWasAskedFor() {
        let terminal = emulator()
        feed(terminal, "\(esc)[38;2;255;128;0mo\(esc)[48;2;1;2;3mb")
        #expect(terminal.cells[0][0].foreground == Theme.Terminal.RGB(0xff8000))
        #expect(terminal.cells[0][1].background == Theme.Terminal.RGB(0x010203))
    }

    @Test func theDefaultBackgroundIsNotPainted() {
        let terminal = emulator()
        feed(terminal, "x\(esc)[44my")
        #expect(terminal.cells[0][0].background == nil)
        #expect(terminal.cells[0][1].background == Theme.Terminal.ansi[4])
    }

    @Test func inverseSwapsTheColoursIncludingTheDefaults() {
        let terminal = emulator()
        feed(terminal, "\(esc)[7mx")
        #expect(terminal.cells[0][0].background == Theme.Terminal.foreground)
        #expect(terminal.cells[0][0].foreground == Theme.Terminal.background)
    }

    @Test func attributesAreReadBack() {
        let terminal = emulator()
        feed(terminal, "\(esc)[1;3;4;9mx\(esc)[0my")
        #expect(terminal.cells[0][0].attributes == [.bold, .italic, .underline, .strikethrough])
        #expect(terminal.cells[0][1].attributes == [])
    }

    // MARK: Scrollback

    @Test func outputPastTheScreenIsKeptAndCanBeScrolledTo() {
        let terminal = emulator(rows: 5)
        feed(terminal, (1...30).map { "line\($0)" }.joined(separator: "\r\n"))
        #expect(line(terminal, 4) == "line30")
        #expect(terminal.scroll.isAtBottom)

        terminal.scroll(by: -10)
        terminal.update()
        #expect(!terminal.scroll.isAtBottom)
        #expect(line(terminal, 0) == "line16")

        terminal.scrollToBottom()
        terminal.update()
        #expect(line(terminal, 4) == "line30")
    }

    // MARK: Selection

    @Test func aWordIsSelectedWhole() {
        let terminal = emulator()
        feed(terminal, "hello world")
        terminal.selectWord(column: 8, row: 0)
        terminal.update()
        #expect(terminal.selectedText == "world")
        #expect(terminal.cells[0][6].isSelected)
        #expect(!terminal.cells[0][0].isSelected)
    }

    @Test func aDragSelectsBetweenTwoCells() {
        let terminal = emulator()
        feed(terminal, "hello world")
        terminal.select(from: (0, 0), to: (4, 0))
        #expect(terminal.selectedText == "hello")
    }

    @Test func aDragMayRunBackwards() {
        let terminal = emulator()
        feed(terminal, "hello world")
        terminal.select(from: (4, 0), to: (0, 0))
        #expect(terminal.selectedText == "hello")
    }

    @Test func aLineIsSelectedWhole() {
        let terminal = emulator()
        feed(terminal, "first line\r\nsecond line")
        terminal.selectLine(column: 3, row: 1)
        #expect(terminal.selectedText == "second line")
    }

    @Test func aSelectionSpanningRowsKeepsItsLineBreaks() {
        let terminal = emulator()
        feed(terminal, "one\r\ntwo\r\nthree")
        terminal.select(from: (0, 0), to: (4, 2))
        #expect(terminal.selectedText == "one\ntwo\nthree")
    }

    @Test func clearingTheSelectionLeavesNone() {
        let terminal = emulator()
        feed(terminal, "hello")
        terminal.selectWord(column: 1, row: 0)
        terminal.clearSelection()
        #expect(terminal.selectedText == nil)
    }

    // MARK: What the program asks for

    @Test func aStatusQueryIsAnsweredToThePty() {
        let terminal = emulator()
        var reply = Data()
        terminal.onReply = { reply.append($0) }
        feed(terminal, "\(esc)[5n")
        #expect(String(decoding: reply, as: UTF8.self) == "\(esc)[0n")
    }

    @Test func theCursorPositionIsReportedWhenAsked() {
        let terminal = emulator()
        var reply = Data()
        terminal.onReply = { reply.append($0) }
        feed(terminal, "ab\(esc)[6n")
        #expect(String(decoding: reply, as: UTF8.self) == "\(esc)[1;3R")
    }

    @Test func theBellRings() {
        let terminal = emulator()
        var rings = 0
        terminal.onBell = { rings += 1 }
        feed(terminal, "\u{7}\u{7}")
        #expect(rings == 2)
    }

    @Test func aProgramMayWriteTheClipboard() {
        let terminal = emulator()
        var written: String?
        terminal.onClipboardWrite = { written = $0 }
        feed(terminal, "\(esc)]52;c;aGVsbG8=\u{7}")
        #expect(written == "hello")
    }

    @Test func aProgramMayNotReadTheClipboard() {
        let terminal = emulator()
        var reply = Data()
        terminal.onReply = { reply.append($0) }
        feed(terminal, "\(esc)]52;c;?\u{7}")
        #expect(reply.isEmpty)
    }

    @Test func aShellsDirectoryIsReported() {
        let terminal = emulator()
        var reported: URL?
        terminal.onWorkingDirectory = { reported = $0 }
        feed(terminal, "\(esc)]7;file://host/tmp/some%20dir\u{7}")
        #expect(reported?.path(percentEncoded: false) == "/tmp/some dir")
    }

    @Test func mouseTrackingFollowsTheProgram() {
        let terminal = emulator()
        #expect(!terminal.isTrackingMouse)
        feed(terminal, "\(esc)[?1000h")
        #expect(terminal.isTrackingMouse)
        feed(terminal, "\(esc)[?1000l")
        #expect(!terminal.isTrackingMouse)
    }

    @Test func thePointerShapeStartsAsTheIBeam() {
        #expect(emulator().mouseShape == .text)
    }

    @Test func aPointerShapeIsReported() {
        let terminal = emulator()
        feed(terminal, "\(esc)]22;pointer\(esc)\\")
        #expect(terminal.mouseShape == .pointer)
        feed(terminal, "\(esc)]22;default\(esc)\\")
        #expect(terminal.mouseShape == .default)
    }

    @Test func aFullResetRestoresTheIBeam() {
        let terminal = emulator()
        feed(terminal, "\(esc)]22;pointer\(esc)\\")
        feed(terminal, "\(esc)c")
        #expect(terminal.mouseShape == .text)
    }

    @Test func theAlternateScreenIsNoticed() {
        let terminal = emulator()
        #expect(!terminal.isOnAlternateScreen)
        feed(terminal, "\(esc)[?1049h")
        #expect(terminal.isOnAlternateScreen)
    }

    // MARK: Input

    @Test func aPrintableKeyIsItsText() {
        let terminal = emulator()
        let bytes = terminal.encode(key: 0, action: .press, modifiers: [], text: "a", unshifted: 0x61)
        #expect(String(decoding: bytes, as: UTF8.self) == "a")
    }

    @Test func returnIsACarriageReturn() {
        let terminal = emulator()
        #expect(terminal.encode(key: 36, action: .press, modifiers: [], text: "\r", unshifted: 0) == Data([0x0d]))
    }

    @Test func controlCIsEndOfText() {
        let terminal = emulator()
        #expect(terminal.encode(key: 8, action: .press, modifiers: .control, text: nil, unshifted: 0x63) == Data([0x03]))
    }

    @Test func optionIsAltAndSendsAnEscapePrefix() {
        let terminal = emulator()
        let bytes = terminal.encode(key: 11, action: .press, modifiers: .option, text: "b", unshifted: 0x62)
        #expect(bytes == Data([0x1b, 0x62]))
    }

    @Test func anArrowKeyFollowsTheCursorKeyMode() {
        let terminal = emulator()
        #expect(terminal.encode(key: 126, action: .press, modifiers: [], text: nil, unshifted: 0) == Data("\(esc)[A".utf8))
        feed(terminal, "\(esc)[?1h")
        #expect(terminal.encode(key: 126, action: .press, modifiers: [], text: nil, unshifted: 0) == Data("\(esc)OA".utf8))
    }

    @Test func aKeyWithNoMappingSendsNothing() {
        let terminal = emulator()
        #expect(terminal.encode(key: 200, action: .press, modifiers: [], text: nil, unshifted: 0).isEmpty)
    }

    @Test func pastedNewlinesAreCarriageReturns() {
        let terminal = emulator()
        #expect(terminal.encodePaste("a\nb") == Data("a\rb".utf8))
    }

    @Test func aPasteIsBracketedWhenTheProgramAsked() {
        let terminal = emulator()
        feed(terminal, "\(esc)[?2004h")
        #expect(terminal.encodePaste("ls") == Data("\(esc)[200~ls\(esc)[201~".utf8))
    }
}
