import AppKit
import Core
import Foundation
import Testing

@testable import EditorFeature

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

    /// Tokens for text the buffer no longer holds change nothing, so there is
    /// nothing to draw either.
    @Test func tokensForOtherTextDoNotTouchTheView() {
        let (buffer, textView) = drawn("let name = \"Herder\"\n")
        #expect(textView.needsDisplay == false)

        buffer.colour([SyntaxToken(range: NSRange(location: 0, length: 3), kind: .keyword)], foundIn: "something else")

        #expect(textView.needsDisplay == false)
    }
}
