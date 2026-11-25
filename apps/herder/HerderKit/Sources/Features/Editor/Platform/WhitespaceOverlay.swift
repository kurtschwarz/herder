import AppKit
import Core
import DesignSystem

/// Draws the markers for whitespace over the text.
///
/// A sibling laid over the scroll view, like ``CurrentLineHighlight`` under it,
/// rather than anything in the text: the markers are never characters, so
/// copying, saving, the caret and the columns cannot see them. It lets every
/// click through.
final class WhitespaceOverlay: NSView {
    private weak var textView: NSTextView?

    var mode = ShowWhitespace.none {
        didSet {
            if mode != oldValue { needsDisplay = true }
        }
    }

    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: Theme.Size.code, weight: .regular),
        .foregroundColor: NSColor(Theme.Palette.whitespace),
    ]

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

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    @objc private func scrolled(_ note: Notification) {
        needsDisplay = true
    }

    /// The text changed. Its layout is not done until after this pass, so it
    /// is drawn again on the next turn too. See the gutter.
    func textDidChange() {
        needsDisplay = true
        // CONCURRENCY: a deferral to the next turn of the run loop, which
        // `Task { @MainActor }` does not promise.
        DispatchQueue.main.async { [weak self] in self?.needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard
            mode != .none,
            let textView,
            let layout = textView.textLayoutManager,
            let content = layout.textContentManager,
            let viewport = layout.textViewportLayoutController.viewportRange
        else { return }

        let start = content.offset(from: content.documentRange.location, to: viewport.location)
        let length = content.offset(from: viewport.location, to: viewport.endLocation)
        let text = textView.string as NSString
        let origin = textView.textContainerOrigin

        for marker in WhitespaceMarker.find(in: text, touching: NSRange(location: start, length: length), mode: mode) {
            guard
                let from = content.location(content.documentRange.location, offsetBy: marker.location),
                let to = content.location(from, offsetBy: 1),
                let range = NSTextRange(location: from, end: to)
            else { continue }
            var frame: NSRect?
            layout.enumerateTextSegments(in: range, type: .standard, options: []) { _, rect, _, _ in
                frame = rect
                return false
            }
            guard let frame else { continue }

            let glyph = NSAttributedString(string: marker.kind.glyph, attributes: Self.attributes)
            let size = glyph.size()
            let x: CGFloat
            switch marker.kind {
            case .space: x = frame.minX + (frame.width - size.width) / 2
            case .tab, .lineEnding: x = frame.minX
            }
            let point = convert(
                NSPoint(x: x + origin.x, y: frame.minY + origin.y + (frame.height - size.height) / 2),
                from: textView
            )
            glyph.draw(at: point)
        }
    }
}
