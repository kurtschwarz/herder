import AppKit
import Core
import Foundation
import Testing

@testable import EditorFeature
@testable import DesignSystem

/// The pane's own behaviour, below the model: what the text view is told when
/// the colour changes under it.
@MainActor
@Suite struct BufferTests {
    /// A buffer whose pane is mounted in a layer-backed window, as SwiftUI
    /// mounts it, and has drawn once, so nothing in it needs display and
    /// anything that does is this test's doing.
    private func drawn(_ text: String) -> (Buffer, NSTextView) {
        let buffer = Buffer(text: text)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.wantsLayer = true
        let pane = buffer.pane
        pane.frame = window.contentView?.bounds ?? .zero
        window.contentView?.addSubview(pane)
        // The pane lays its two children out itself, and a text view with no
        // size has no paragraphs to put in views.
        pane.layoutSubtreeIfNeeded()
        window.contentView?.displayIfNeeded()
        return (buffer, pane.scrollView.documentView as! NSTextView)
    }

    /// Every view under `view` that has nothing waiting to be drawn.
    private func clean(under view: NSView) -> [NSView] {
        view.subviews.flatMap { ($0.needsDisplay ? [] : [$0]) + clean(under: $0) }
    }

    /// The views a text view paints its paragraphs into, which sit a level
    /// below its own children: those are containers, and one of them draws
    /// the selection and clears its own flag when there is none.
    private func paragraphs(of textView: NSTextView) -> [NSView] {
        textView.subviews.flatMap(\.subviews)
    }

    /// TextKit paints each paragraph into a view of its own inside the text
    /// view, and colour is a rendering attribute rather than an edit, so
    /// nothing dirties those views for it. Without this the tokens were right
    /// and invisible until the caret next blinked, a second later, which
    /// looked like a slow highlighter.
    @Test func colouringAsksEveryParagraphToDrawAgain() {
        let text = String(repeating: "let name = \"Herder\"\n", count: 20)
        let (buffer, textView) = drawn(text)
        let views = paragraphs(of: textView)
        let cleanBefore = views.filter { !$0.needsDisplay } + views.flatMap(clean(under:))
        #expect(!views.isEmpty)
        #expect(!cleanBefore.isEmpty)

        buffer.colour([SyntaxToken(range: NSRange(location: 0, length: 3), kind: .keyword)], foundIn: text)

        let cleanAfter = views.filter { !$0.needsDisplay } + views.flatMap(clean(under:))
        #expect(cleanAfter.isEmpty)
    }

    /// The fragments laid out for `textView`'s paragraphs, in order.
    private func fragments(of textView: NSTextView) -> [WhitespaceLayoutFragment] {
        var found: [WhitespaceLayoutFragment] = []
        textView.textLayoutManager?.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
            if let fragment = fragment as? WhitespaceLayoutFragment { found.append(fragment) }
            return true
        }
        return found
    }

    /// The markers are drawn by the paragraphs, so every paragraph has to be
    /// one that can, and a change of mode has to reach those already made.
    @Test func everyParagraphFollowsTheWhitespaceMode() {
        let (buffer, textView) = drawn("a b\nc\n")
        let laidOut = fragments(of: textView)
        #expect(laidOut.count == 2)
        #expect(laidOut.allSatisfy { $0.mode == .none && $0.markers().isEmpty })

        buffer.showWhitespace = .all

        #expect(fragments(of: textView).allSatisfy { $0.mode == .all })
    }

    /// The same as colour: a new mode is no edit, so nothing else would
    /// redraw the paragraphs.
    @Test func changingTheModeAsksEveryParagraphToDrawAgain() {
        let (buffer, textView) = drawn(String(repeating: "let name = 1\n", count: 20))
        let views = paragraphs(of: textView)
        #expect(!(views.filter { !$0.needsDisplay } + views.flatMap(clean(under:))).isEmpty)

        buffer.showWhitespace = .all

        #expect((views.filter { !$0.needsDisplay } + views.flatMap(clean(under:))).isEmpty)
    }

    @Test func aParagraphMadeAfterTheModeChangedHasIt() {
        let (buffer, textView) = drawn("a\n")
        buffer.showWhitespace = .trailing

        textView.insertText("b  \n", replacementRange: NSRange(location: 2, length: 0))

        let laidOut = fragments(of: textView)
        #expect(laidOut.allSatisfy { $0.mode == .trailing })
        #expect(laidOut.last?.markers().map(\.kind) == [.space, .space])
    }

    /// A tab's arrow at the tab's start, a space's dot inside its own width,
    /// and a line ending's hook right after the last character.
    @Test func markersArePlacedOnTheCharactersTheyMark() throws {
        let (buffer, textView) = drawn("a\tb c\n")
        buffer.showWhitespace = .all
        let fragment = try #require(fragments(of: textView).first)
        let line = try #require(fragment.textLineFragments.first)
        func x(_ offset: Int) -> CGFloat { line.typographicBounds.minX + line.locationForCharacter(at: offset).x }

        let markers = fragment.markers()

        #expect(markers.map(\.kind) == [.tab, .space, .lineEnding])
        #expect(markers[0].origin.x == x(1))
        #expect(markers[1].origin.x > x(3) && markers[1].origin.x < x(4))
        #expect(markers[2].origin.x == x(5))
        #expect(markers.allSatisfy { $0.origin.y == line.typographicBounds.minY })
    }

    @Test func aFinalLineWithNoNewlineHasNoHook() throws {
        let (buffer, textView) = drawn("a\nb")
        buffer.showWhitespace = .all

        let laidOut = fragments(of: textView)

        #expect(laidOut.map { $0.markers().map(\.kind) } == [[.lineEnding], []])
    }

    /// The colour painted over the character at `offset`, or `nil` for none.
    ///
    /// The enumeration skips ahead to the next coloured run rather than
    /// reporting an uncoloured one, so the run found has to contain `offset`.
    private func colour(in buffer: Buffer, at offset: Int) -> NSColor? {
        let layout = buffer.pane.scrollView.documentView.flatMap { ($0 as? NSTextView)?.textLayoutManager }
        guard let layout, let content = layout.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: offset)
        else { return nil }
        var found: NSColor?
        layout.enumerateRenderingAttributes(from: start, reverse: false) { _, attributes, range in
            if range.contains(start) { found = attributes[.foregroundColor] as? NSColor }
            return false
        }
        return found
    }

    /// Between a keystroke and the next parse, the colour after the caret has
    /// to move with its text rather than stay where the text was.
    @Test func colourFollowsTextTypedBeforeIt() {
        let text = "let name = \"Herder\"\n"
        let (buffer, textView) = drawn(text)
        let string = (text as NSString).range(of: "\"Herder\"")
        buffer.colour([SyntaxToken(range: string, kind: .string)], foundIn: text)
        let stringColour = SyntaxAttributes.colour(for: .string)
        #expect(colour(in: buffer, at: string.location) == stringColour)

        buffer.storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "xxx")
        buffer.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        #expect(buffer.text.hasPrefix("xxx"))
        #expect(colour(in: buffer, at: string.location + 3) == stringColour)
        #expect(colour(in: buffer, at: string.location + 3 + string.length - 1) == stringColour)
        #expect(colour(in: buffer, at: string.location) != stringColour)
    }

    /// TextKit may grow a coloured span over text typed at its edge. The parse
    /// finds the same tokens as the shifted ones there, so nothing differs to
    /// repaint, and only repainting what was typed puts it right.
    @Test func textTypedAtATokensEdgeIsRepaintedEvenWhenTheTokensAgree() {
        let text = "let name = \"Herder\"\n"
        let (buffer, textView) = drawn(text)
        let string = (text as NSString).range(of: "\"Herder\"")
        buffer.colour([SyntaxToken(range: string, kind: .string)], foundIn: text)
        let stringColour = SyntaxAttributes.colour(for: .string)

        let end = NSMaxRange(string)
        buffer.storage.replaceCharacters(in: NSRange(location: end, length: 0), with: "x")
        buffer.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        buffer.colour([SyntaxToken(range: string, kind: .string)], foundIn: buffer.text)

        #expect(colour(in: buffer, at: end - 1) == stringColour)
        #expect(colour(in: buffer, at: end) != stringColour)
    }

    /// Sizes the two costs behind the colour lag. Prints, and asserts nothing
    /// about time: a budget here would fail on a busy machine.
    @Test func colouringALargeFileIsTimed() {
        let line = "let name = \"Herder\" // note\n"
        let text = String(repeating: line, count: 5_000)
        let buffer = Buffer(text: text)
        _ = buffer.pane
        var tokens: [SyntaxToken] = []
        var location = 0
        for _ in 0..<5_000 {
            tokens.append(SyntaxToken(range: NSRange(location: location, length: 3), kind: .keyword))
            tokens.append(SyntaxToken(range: NSRange(location: location + 11, length: 8), kind: .string))
            location += (line as NSString).length
        }

        let clock = ContinuousClock()
        let elapsed = clock.measure { buffer.colour(tokens, foundIn: text) }
        print("colour: \(tokens.count) tokens in \(text.utf16.count) UTF-16 units took \(elapsed)")

        // A keystroke in the middle: the parse finds the shifted tokens again.
        let middle = text.utf16.count / 2
        buffer.storage.replaceCharacters(in: NSRange(location: middle, length: 0), with: "x")
        let shifted = tokens.applying(TextEdit(replaced: NSRange(location: middle, length: 0), length: 1))
        let keystroke = clock.measure { buffer.colour(shifted, foundIn: buffer.text) }
        print("colour after one keystroke took \(keystroke)")
    }

    // MARK: Going to a place

    @Test func aLineAndColumnAreAnOffsetInTheText() {
        let text = "one\ntwo\nthree four\n"
        #expect(Buffer.offset(line: 1, column: nil, in: text) == 0)
        #expect(Buffer.offset(line: 2, column: nil, in: text) == 4)
        #expect(Buffer.offset(line: 3, column: 3, in: text) == 10)
        #expect(Buffer.offset(line: 3, column: 1, in: text) == 8)
    }

    @Test func aColumnPastTheEndOfItsLineIsTheEndOfTheLine() {
        let text = "one\ntwo\nthree four\n"
        #expect(Buffer.offset(line: 2, column: 99, in: text) == 7)
        #expect(Buffer.offset(line: 3, column: 99, in: text) == 18)
    }

    @Test func aLinePastTheEndOfTheTextIsTheLastLine() {
        #expect(Buffer.offset(line: 99, column: 2, in: "one\ntwo") == 5)
        #expect(Buffer.offset(line: 5, column: nil, in: "") == 0)
    }

    @Test func revealingPutsTheCaretThere() {
        let buffer = Buffer(text: "one\ntwo\nthree four\n")
        buffer.reveal(line: 3, column: 3)
        #expect(buffer.selectedRange == NSRange(location: 10, length: 0))
    }

    /// Tokens for text the buffer no longer holds change nothing, so there is
    /// nothing to draw either.
    @Test func tokensForOtherTextDoNotTouchTheView() {
        let (buffer, textView) = drawn("let name = \"Herder\"\n")
        #expect(textView.needsDisplay == false)

        buffer.colour([SyntaxToken(range: NSRange(location: 0, length: 3), kind: .keyword)], foundIn: "something else")

        #expect(textView.needsDisplay == false)
    }
}
