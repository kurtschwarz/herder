import AppKit
import Core

/// Gives TextKit a ``WhitespaceLayoutFragment`` for every paragraph, so the
/// markers are drawn with the text rather than over it.
///
/// Nonisolated because TextKit asks for fragments from whichever thread lays
/// out; the text view lays out on the main thread.
nonisolated final class WhitespaceFragmentSource: NSObject, NSTextLayoutManagerDelegate {
    /// What a fragment made from now on marks. The ones already made are
    /// told by whoever changes it.
    var mode = ShowWhitespace.none

    private let glyphs: WhitespaceLayoutFragment.Glyphs

    init(attributes: [NSAttributedString.Key: Any]) {
        glyphs = WhitespaceLayoutFragment.Glyphs(attributes: attributes)
    }

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let fragment = WhitespaceLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.mode = mode
        fragment.glyphs = glyphs
        return fragment
    }
}
