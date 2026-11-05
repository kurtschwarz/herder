import AppKit
import DesignSystem
import SwiftUI
import Syntax

/// A read-only, selectable text view with a line-number gutter.
///
/// TextKit 2 under an `NSScrollView`: contiguous selection, copy and find come
/// with it, and it is the same view an editable one would be. Lines do not wrap,
/// so a gutter number is one per line.
struct CodeTextView: NSViewRepresentable {
    /// The text and its tokens, which arrive together so colour can never be
    /// applied to a string it was not computed for.
    let source: SourceText

    /// Which opening this is. A new one starts at the top; a re-read of the same
    /// file keeps its place.
    let session: Int

    final class Coordinator {
        var session: Int?

        /// What was last put into the view, so an identical update does no work.
        /// The text alone is not enough: the same text can arrive with tokens
        /// after arriving without them.
        var source: SourceText?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = textView.maxSize
        textView.textContainerInset = NSSize(width: Theme.Spacing.normal, height: Theme.Spacing.normal)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.clipsToBounds = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true

        scrollView.verticalRulerView = LineNumberRuler(scrollView: scrollView, textView: textView)
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard
            let textView = scrollView.documentView as? NSTextView,
            let storage = textView.textStorage
        else { return }

        let isNewFile = context.coordinator.session != session
        context.coordinator.session = session
        guard isNewFile || context.coordinator.source != source else { return }
        context.coordinator.source = source

        let offset = scrollView.contentView.bounds.origin
        // One editing transaction: the base pass rewrites every character and
        // each token then overwrites part of it, and laying out between them
        // would be laying out work that is about to be replaced.
        storage.beginEditing()
        storage.setAttributedString(NSAttributedString(string: source.text, attributes: SyntaxAttributes.base))
        for token in source.tokens where NSMaxRange(token.range) <= storage.length {
            storage.addAttributes(SyntaxAttributes.attributes(for: token.kind), range: token.range)
        }
        storage.endEditing()
        // The selection does not survive: a character range means nothing once
        // the text under it has been rewritten.
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        let clip = scrollView.contentView
        if isNewFile {
            clip.scroll(to: .zero)
        } else {
            textView.layoutSubtreeIfNeeded()
            clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: offset, size: clip.bounds.size)).origin)
        }
        scrollView.reflectScrolledClipView(clip)

        (scrollView.verticalRulerView as? LineNumberRuler)?.textDidChange(to: source.text)
    }
}
