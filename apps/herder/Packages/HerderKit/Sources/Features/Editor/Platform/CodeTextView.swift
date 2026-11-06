import AppKit
import Core
import DesignSystem
import SwiftUI

/// A read-only, selectable text view with a line-number gutter.
///
/// TextKit 2 under an `NSScrollView`: contiguous selection, copy and find come
/// with it, and it is the same view an editable one would be. Lines do not wrap,
/// so a gutter number is one per line.
struct CodeTextView: NSViewRepresentable {
    /// The text and its tokens, which arrive together so colour can never be
    /// applied to a string it was not computed for.
    let source: SourceText

    /// Which opening this is. A new one goes to ``restoring``; a re-read of the
    /// same file keeps where it is.
    let session: Int

    /// Where this tab was last left. `.zero` for one never scrolled, which is
    /// the top.
    let restoring: CGPoint

    /// Reports where the tab being left was, so coming back to it can restore
    /// it. Called when the session changes under a mounted view, and when the
    /// view goes away — which is what a tab switch actually does, since the
    /// pane blanks while the next file is read.
    let onLeave: (CGPoint) -> Void

    final class Coordinator {
        var session: Int?

        /// What was last put into the view, so an identical update does no work.
        /// The text alone is not enough: the same text can arrive with tokens
        /// after arriving without them.
        var source: SourceText?

        /// The *previous* value of ``CodeTextView/onLeave``, so the offset on
        /// screen is reported against the tab it belongs to rather than the one
        /// arriving.
        var onLeave: ((CGPoint) -> Void)?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> CodePane {
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

        return CodePane(
            scrollView: scrollView,
            gutter: LineNumberGutter(scrollView: scrollView, textView: textView)
        )
    }

    func updateNSView(_ pane: CodePane, context: Context) {
        let scrollView = pane.scrollView
        guard
            let textView = scrollView.documentView as? NSTextView,
            let storage = textView.textStorage
        else { return }

        let isNewFile = context.coordinator.session != session
        let offset = scrollView.contentView.bounds.origin
        // Still the outgoing tab's offset: the text has not been replaced yet.
        if isNewFile { context.coordinator.onLeave?(offset) }
        context.coordinator.onLeave = onLeave
        context.coordinator.session = session
        guard isNewFile || context.coordinator.source != source else { return }
        context.coordinator.source = source

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
        // Before constraining: a remembered offset deeper than this text can
        // reach has to be clamped against the laid-out height, not the old one.
        textView.layoutSubtreeIfNeeded()
        let target = isNewFile ? restoring : offset
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: target, size: clip.bounds.size)).origin)
        scrollView.reflectScrolledClipView(clip)

        pane.gutter.textDidChange(to: source.text)
    }

    /// A tab switch blanks the pane while the next file is read, which takes
    /// this view with it. Without this the offset of the tab being left would
    /// never be recorded.
    static func dismantleNSView(_ pane: CodePane, coordinator: Coordinator) {
        coordinator.onLeave?(pane.scrollView.contentView.bounds.origin)
    }
}
