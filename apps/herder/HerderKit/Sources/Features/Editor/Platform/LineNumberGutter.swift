import AppKit
import DesignSystem

/// Numbers the lines of a TextKit 2 text view.
///
/// Draws only the fragments in view. A line's number is found by searching the
/// offsets at which lines start, which are worked out once per text rather than
/// on every scroll.
///
/// A sibling of the scroll view rather than an `NSRulerView`: AppKit lays a
/// ruler over the clip view instead of beside it, so a line long enough to
/// scroll sideways was drawn under the numbers. Side by side, the scroll view's
/// own edge is where the text stops.
final class LineNumberGutter: NSView {
    private weak var textView: NSTextView?

    /// UTF-16 offset of the start of each line, the unit `NSTextContentManager`
    /// measures in.
    private var lineStarts = [0]

    /// Whether the text ends after a newline, or is empty, so the last line has
    /// nothing in it. TextKit makes no layout fragment for that line, though
    /// the caret can sit on it, so it has to be numbered without one.
    private var endsInEmptyLine = true

    private let font = NSFont.monospacedDigitSystemFont(ofSize: Theme.Size.code, weight: .regular)

    private let attributes: [NSAttributedString.Key: Any]
    private let currentAttributes: [NSAttributedString.Key: Any]

    /// Width of the strip at the right edge, between the numbers and the text,
    /// where a changed line's bar and a deleted boundary's triangle are drawn.
    /// Inside the gutter's own width, so the numbers give way to it.
    private static let stripWidth: CGFloat = 3

    private static let addedColour = NSColor(Theme.Palette.success)
    private static let modifiedColour = NSColor(Theme.Palette.warning)
    private static let deletedColour = NSColor(Theme.Palette.danger)

    /// The lines that differ from `HEAD`. Display only: the gutter draws what
    /// it is given.
    var changes = LineChanges.none {
        didSet {
            if changes != oldValue { needsDisplay = true }
        }
    }

    /// The 1-based lines the caret is on or a selection touches. A selection
    /// that ends where a line starts, as a triple-click's does, leaves that
    /// line out: nothing on it is selected.
    private var currentLines: IndexSet {
        var lines = IndexSet()
        for value in textView?.selectedRanges ?? [] {
            let range = value.rangeValue
            let last = range.length == 0 ? range.location : NSMaxRange(range) - 1
            lines.insert(integersIn: number(at: range.location)...number(at: last))
        }
        return lines
    }

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        attributes = [.font: font, .foregroundColor: NSColor(Theme.Palette.tertiaryText)]
        currentAttributes = [.font: font, .foregroundColor: NSColor(Theme.Palette.text)]
        super.init(frame: .zero)
        // Views stopped clipping to their bounds by default in macOS 14, and a
        // number for a line scrolled half out of view would be drawn over the
        // breadcrumb above.
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
    }

    func textDidChange(to text: String) {
        var starts = [0]
        for (offset, unit) in text.utf16.enumerated() where unit == 0x0A {
            starts.append(offset + 1)
        }
        lineStarts = starts
        endsInEmptyLine = starts.last == text.utf16.count
        needsDisplay = true
        // Layout is lazy and has not happened yet, so what is in view is not
        // known until after this pass.
        //
        // CONCURRENCY: a deferral to the next turn of the run loop, which is
        // what AppKit wants here and what `Task { @MainActor }` does not
        // promise — a task may run before the layout pass this is waiting out.
        DispatchQueue.main.async { [weak self] in self?.needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard
            let textView,
            let layout = textView.textLayoutManager,
            let content = layout.textContentManager
        else { return }

        let originY = textView.textContainerOrigin.y
        let currentLines = currentLines
        let start = layout.textViewportLayoutController.viewportRange?.location ?? layout.documentRange.location

        // Where the empty line after the last fragment has its baseline.
        var emptyLineBaseline: CGFloat?
        var reachedEnd = true
        let lastLine = endsInEmptyLine ? lineStarts.count - 1 : lineStarts.count

        layout.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            // Converted rather than subtracted from the scroll offset: with a
            // bar over the top, the scroll view has a content inset and the
            // gutter's own origin is not the clip view's.
            let top = convert(NSPoint(x: 0, y: fragment.layoutFragmentFrame.minY + originY), from: textView).y
            if top > bounds.height {
                reachedEnd = false
                return false
            }
            guard let line = fragment.textLineFragments.first else { return true }
            // A paragraph ending in a newline carries the empty line after
            // it as a second line fragment of its own, which is where the
            // caret goes. Only the first is numbered above, as a wrapped
            // line's others are not.
            if let tail = fragment.textLineFragments.last, fragment.textLineFragments.count > 1 {
                emptyLineBaseline = top + tail.typographicBounds.minY + tail.glyphOrigin.y
            } else {
                emptyLineBaseline = top + fragment.layoutFragmentFrame.height
                    + line.typographicBounds.minY + line.glyphOrigin.y
            }

            let offset = content.offset(from: layout.documentRange.location, to: fragment.rangeInElement.location)
            let lineNumber = number(at: offset)
            let label = NSAttributedString(
                string: "\(lineNumber)",
                attributes: numberAttributes(for: lineNumber, isCurrent: currentLines.contains(lineNumber))
            )
            let size = label.size()
            // Sat on the text's own baseline. Centring in the line box drifts
            // when the two fonts' ascents differ.
            let baseline = top + line.typographicBounds.minY + line.glyphOrigin.y
            label.draw(at: NSPoint(
                x: bounds.width - size.width - Theme.Spacing.normal - Self.stripWidth,
                y: baseline - font.ascender
            ))
            let isLast = lineNumber == lastLine
            // The last line's fragment includes the empty line after it, which
            // is no part of the line that changed.
            var height = fragment.layoutFragmentFrame.height
            if isLast, endsInEmptyLine, let tail = fragment.textLineFragments.last, fragment.textLineFragments.count > 1 {
                height = tail.typographicBounds.minY
            }
            drawMarkers(for: lineNumber, top: top, height: height, isLast: isLast)
            return true
        }

        guard reachedEnd, endsInEmptyLine else { return }
        let baseline = emptyLineBaseline ?? convert(NSPoint(x: 0, y: originY), from: textView).y + font.ascender
        let label = NSAttributedString(
            string: "\(lineStarts.count)",
            attributes: currentLines.contains(lineStarts.count) ? currentAttributes : attributes
        )
        label.draw(at: NSPoint(
            x: bounds.width - label.size().width - Theme.Spacing.normal - Self.stripWidth,
            y: baseline - font.ascender
        ))
    }

    /// A changed line's number takes its marker's colour, and the current line
    /// still reads brighter than the rest.
    private func numberAttributes(for line: Int, isCurrent: Bool) -> [NSAttributedString.Key: Any] {
        guard let colour = colour(forLine: line) else { return isCurrent ? currentAttributes : attributes }
        return [.font: font, .foregroundColor: isCurrent ? colour : colour.withAlphaComponent(0.65)]
    }

    private func colour(forLine line: Int) -> NSColor? {
        if changes.added.contains(line) { return Self.addedColour }
        if changes.modified.contains(line) { return Self.modifiedColour }
        return nil
    }

    /// Draws what the strip shows for `line`, which fills `top` down by
    /// `height`: its bar if it changed, and a triangle where lines were removed
    /// above it. A removal after the last line has no line below it, so it is
    /// drawn at the bottom of that one.
    private func drawMarkers(for line: Int, top: CGFloat, height: CGFloat, isLast: Bool) {
        if let colour = colour(forLine: line) {
            colour.setFill()
            NSRect(x: bounds.width - Self.stripWidth, y: top, width: Self.stripWidth, height: height).fill()
        }
        if changes.deleted.contains(line - 1) { drawTriangle(at: top) }
        if isLast, changes.deleted.contains(line) { drawTriangle(at: top + height) }
    }

    /// A small triangle pointing at the text, centred on `y`.
    private func drawTriangle(at y: CGFloat) {
        let edge = bounds.width
        let path = NSBezierPath()
        path.move(to: NSPoint(x: edge - Self.stripWidth, y: y - Self.stripWidth))
        path.line(to: NSPoint(x: edge, y: y))
        path.line(to: NSPoint(x: edge - Self.stripWidth, y: y + Self.stripWidth))
        path.close()
        Self.deletedColour.setFill()
        path.fill()
    }

    /// The 1-based line holding the character at `offset`.
    private func number(at offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count
        while low < high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= offset { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
