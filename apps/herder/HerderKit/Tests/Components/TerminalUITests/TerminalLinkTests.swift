import Foundation
import Testing

@testable import TerminalUI

/// Against the real libghostty-vt: what a program marks as a link (OSC 8), and
/// what is found in the text, as they come back out of the grid.
@Suite struct TerminalLinkTests {
    let esc = "\u{1b}"

    func emulator(columns: Int = 20, rows: Int = 6, existing: Set<String> = []) -> TerminalEmulator {
        let terminal = TerminalEmulator(columns: columns, rows: rows, scrollbackLines: 100)
        terminal.workingDirectory = URL(filePath: "/work/repo", directoryHint: .isDirectory)
        terminal.homeDirectory = URL(filePath: "/Users/kurt", directoryHint: .isDirectory)
        terminal.fileExists = { existing.contains($0.path(percentEncoded: false)) }
        return terminal
    }

    @discardableResult
    func feed(_ emulator: TerminalEmulator, _ text: String) -> Set<Int> {
        emulator.write(Data(text.utf8))
        return emulator.update()
    }

    func url(_ string: String) -> TerminalLink.Target { .url(URL(string: string)!) }

    // MARK: Marked by the program

    @Test func aLinkTheProgramMarkedIsFoundOnItsCellsOnly() {
        let terminal = emulator()
        feed(terminal, "a\(esc)]8;;https://example.com\(esc)\\click\(esc)]8;;\(esc)\\ b")
        #expect(terminal.link(atColumn: 0, row: 0) == nil)
        for column in 1...5 { #expect(terminal.link(atColumn: column, row: 0) == url("https://example.com")) }
        #expect(terminal.link(atColumn: 6, row: 0) == nil)
        #expect(terminal.link(atColumn: 7, row: 0) == nil)
    }

    @Test func aFileLinkTheProgramMarkedIsAFile() {
        let terminal = emulator()
        feed(terminal, "\(esc)]8;;file://host/tmp/a%20b.txt\(esc)\\f\(esc)]8;;\(esc)\\")
        #expect(terminal.link(atColumn: 0, row: 0) == .file(URL(filePath: "/tmp/a b.txt"), line: nil, column: nil))
    }

    @Test func twoMarkedLinksOnARowAreTold() {
        let terminal = emulator(columns: 30)
        feed(terminal, "\(esc)]8;;https://a.io\(esc)\\aa\(esc)]8;;https://b.io\(esc)\\bb\(esc)]8;;\(esc)\\")
        #expect(terminal.link(atColumn: 1, row: 0) == url("https://a.io"))
        #expect(terminal.link(atColumn: 2, row: 0) == url("https://b.io"))
    }

    @Test func aMarkedLinkWinsOverTheTextInsideIt() {
        let terminal = emulator(columns: 40)
        feed(terminal, "\(esc)]8;;https://real.io\(esc)\\https://shown.io\(esc)]8;;\(esc)\\")
        #expect(terminal.link(atColumn: 3, row: 0) == url("https://real.io"))
    }

    // MARK: Found in the text

    @Test func aUrlInTheTextIsALink() {
        let terminal = emulator(columns: 40)
        feed(terminal, "see https://x.y/z.")
        #expect(terminal.link(atColumn: 3, row: 0) == nil)
        #expect(terminal.link(atColumn: 4, row: 0) == url("https://x.y/z"))
        #expect(terminal.link(atColumn: 16, row: 0) == url("https://x.y/z"))
        #expect(terminal.link(atColumn: 17, row: 0) == nil)
    }

    @Test func aUrlThatWrapsOntoTheNextRowIsOneLink() {
        let terminal = emulator(columns: 20)
        let changed = feed(terminal, "https://example.com/a/very/long/path")
        let expected = url("https://example.com/a/very/long/path")
        #expect(terminal.link(atColumn: 0, row: 0) == expected)
        #expect(terminal.link(atColumn: 19, row: 0) == expected)
        #expect(terminal.link(atColumn: 0, row: 1) == expected)
        #expect(terminal.link(atColumn: 15, row: 1) == expected)
        #expect(terminal.link(atColumn: 16, row: 1) == nil)
        #expect(changed.isSuperset(of: [0, 1]))
    }

    @Test func aRowThatDidNotChangeIsRedrawnWhenALinkReachesIntoIt() {
        let terminal = emulator(columns: 20)
        feed(terminal, "https://example.com/a")
        #expect(terminal.link(atColumn: 0, row: 0) != nil)
        // The first row is as it was; what follows it on the next changes what it is.
        let changed = feed(terminal, "/very/long/path")
        #expect(terminal.link(atColumn: 0, row: 0) == url("https://example.com/a/very/long/path"))
        #expect(changed.contains(0))
    }

    @Test func aLineIsNotALinkOnceItsTextIsOverwritten() {
        let terminal = emulator(columns: 40)
        feed(terminal, "see https://x.y/z")
        feed(terminal, "\r\(esc)[2Kplain")
        #expect(terminal.link(atColumn: 6, row: 0) == nil)
    }

    @Test func textThatLooksLikeAPathIsALinkOnlyIfSomethingIsThere() {
        let terminal = emulator(columns: 40, existing: ["/work/repo/src/foo.swift"])
        feed(terminal, "src/foo.swift and/or src/gone.swift")
        let file = TerminalLink.Target.file(URL(filePath: "/work/repo/src/foo.swift"), line: nil, column: nil)
        #expect(terminal.link(atColumn: 0, row: 0) == file)
        #expect(terminal.link(atColumn: 12, row: 0) == file)
        #expect(terminal.link(atColumn: 14, row: 0) == nil)
        #expect(terminal.link(atColumn: 20, row: 0) == nil)
        #expect(terminal.link(atColumn: 30, row: 0) == nil)
    }

    @Test func aPathCarriesItsLineAndColumnToTheLink() {
        let terminal = emulator(columns: 40, existing: ["/work/repo/path/to/file.swift"])
        feed(terminal, "path/to/file.swift:42:7")
        #expect(terminal.link(atColumn: 22, row: 0)
            == .file(URL(filePath: "/work/repo/path/to/file.swift"), line: 42, column: 7))
    }

    @Test func aHomePathAndAnAbsolutePathResolveWithoutTheDirectory() {
        let terminal = emulator(columns: 40, existing: ["/Users/kurt/x", "/abs/path"])
        feed(terminal, "~/x /abs/path")
        #expect(terminal.link(atColumn: 0, row: 0) == .file(URL(filePath: "/Users/kurt/x"), line: nil, column: nil))
        #expect(terminal.link(atColumn: 5, row: 0) == .file(URL(filePath: "/abs/path"), line: nil, column: nil))
    }

    @Test func aRelativePathFollowsTheDirectoryTheShellReported() {
        let terminal = emulator(columns: 40, existing: ["/work/repo/sub/a.txt"])
        feed(terminal, "./a.txt")
        #expect(terminal.link(atColumn: 0, row: 0) == nil)

        terminal.workingDirectory = URL(filePath: "/work/repo/sub", directoryHint: .isDirectory)
        feed(terminal, "\r\n./a.txt")
        #expect(terminal.link(atColumn: 0, row: 1)
            == .file(URL(filePath: "/work/repo/sub/a.txt"), line: nil, column: nil))
    }

    @Test func aLinkIsNotMadeOfBlankCells() {
        let terminal = emulator(columns: 40)
        feed(terminal, "https://x.y/z")
        #expect(terminal.link(atColumn: 30, row: 0) == nil)
        #expect(terminal.link(atColumn: 100, row: 0) == nil)
        #expect(terminal.link(atColumn: 0, row: 100) == nil)
        #expect(terminal.link(atColumn: -1, row: 0) == nil)
    }

    @Test func aLinkIsDrawnUnderlined() {
        let terminal = emulator(columns: 40)
        feed(terminal, "https://x.y/z plain")
        #expect(terminal.cells[0][0].link != 0)
        #expect(terminal.cells[0][15].link == 0)
    }
}
