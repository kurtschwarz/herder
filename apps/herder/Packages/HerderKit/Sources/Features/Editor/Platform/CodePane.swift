import AppKit
import DesignSystem

/// The gutter and the scrolling text, side by side.
///
/// The two are siblings so that the scroll view occupies only the space right
/// of the gutter and clips there: text scrolled sideways disappears at the
/// gutter's edge rather than passing under the numbers.
final class CodePane: NSView {
    let scrollView: NSScrollView
    let gutter: LineNumberGutter

    init(scrollView: NSScrollView, gutter: LineNumberGutter) {
        self.scrollView = scrollView
        self.gutter = gutter
        super.init(frame: .zero)
        addSubview(gutter)
        addSubview(scrollView)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layout() {
        super.layout()
        gutter.frame = NSRect(x: 0, y: 0, width: Theme.Size.gutter, height: bounds.height)
        scrollView.frame = NSRect(
            x: Theme.Size.gutter,
            y: 0,
            width: max(0, bounds.width - Theme.Size.gutter),
            height: bounds.height
        )
    }
}
