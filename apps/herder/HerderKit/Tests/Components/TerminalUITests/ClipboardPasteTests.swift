import Foundation
import Testing

@testable import TerminalUI

@Suite struct ClipboardPasteTests {
    let file = URL(filePath: "/tmp/a b.png")

    @Test func fileLinksComeFirst() {
        let choice = ClipboardPaste.choose(fileURLs: [file], text: "a b.png", hasImage: true)
        #expect(choice == .paths("'/tmp/a b.png' "))
    }

    @Test func textComesBeforeAnImage() {
        #expect(ClipboardPaste.choose(fileURLs: [], text: "hi", hasImage: true) == .text("hi"))
    }

    @Test func anImageAloneIsAnImage() {
        #expect(ClipboardPaste.choose(fileURLs: [], text: nil, hasImage: true) == .image)
    }

    @Test func nothingIsNothing() {
        #expect(ClipboardPaste.choose(fileURLs: [], text: nil, hasImage: false) == nil)
    }

    @Test func emptyTextIsStillText() {
        #expect(ClipboardPaste.choose(fileURLs: [], text: "", hasImage: false) == .text(""))
    }

    @Test func pathsAreQuotedAndSeparatedBySpaces() {
        let urls = [URL(filePath: "/tmp/it's"), URL(filePath: "/tmp/b")]
        #expect(ClipboardPaste.quoted(urls) == "'/tmp/it'\\''s' '/tmp/b' ")
    }
}
