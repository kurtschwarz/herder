import AppKit
import DesignSystem
import SwiftUI

/// A read-only, selectable text view with a line-number gutter.
///
/// TextKit 2 under an `NSScrollView`: contiguous selection, copy and find come
/// with it, and it is the same view an editable one would be. Lines do not wrap,
/// so a gutter number is one per line.
struct CodeTextView: NSViewRepresentable {
    let text: String

    /// Which opening this is. A new one starts at the top; a re-read of the same
    /// file keeps its place.
    let session: Int

    final class Coordinator {
        var session: Int?
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
        guard isNewFile || textView.string != text else { return }

        let offset = scrollView.contentView.bounds.origin
        storage.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: Theme.Size.code, weight: .regular),
            .foregroundColor: NSColor(Theme.Palette.text),
        ]))
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

        (scrollView.verticalRulerView as? LineNumberRuler)?.textDidChange(to: text)
    }
}
