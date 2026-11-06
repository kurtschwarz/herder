import AppKit
import DesignSystem

/// The band behind the line the caret is on.
///
/// Laid under both the gutter and the scroll view rather than drawn by the
/// text view, so one band runs the width of the pane, number and all. Neither
/// sibling draws a background, so it shows through both.
///
/// Only for a caret: a selection is already marked by its own highlight.
final class CurrentLineHighlight: NSView {
    private weak var textView: NSTextView?

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
        clipsToBounds = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }

    @objc private func scrolled(_ note: Notification) {
        needsDisplay = true
    }

    func selectionDidChange() {
        needsDisplay = true
        // The selection moves before the text it sits in is laid out, so the
        // line's frame is not known until after this pass. See the gutter.
        //
        // CONCURRENCY: a deferral to the next turn of the run loop, which
        // `Task { @MainActor }` does not promise.
        DispatchQueue.main.async { [weak self] in self?.needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard
            let textView,
            textView.selectedRange().length == 0,
            let layout = textView.textLayoutManager,
            let caret = layout.textSelections.first?.textRanges.first?.location
        else { return }

        var line: NSRect?
        layout.enumerateTextSegments(in: NSTextRange(location: caret), type: .standard, options: []) { _, frame, _, _ in
            line = frame
            return false
        }
        guard let line else { return }

        let top = convert(NSPoint(x: 0, y: line.minY + textView.textContainerOrigin.y), from: textView).y
        NSColor(Theme.Palette.currentLine).setFill()
        NSRect(x: 0, y: top, width: bounds.width, height: line.height).fill()
    }
}
