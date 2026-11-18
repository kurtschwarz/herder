import AppKit

/// An `NSTextView` that says when its selection moves, mid-click included.
///
/// `didChangeSelectionNotification` and the delegate are only told once the
/// mouse comes up: while the button is held the selection is "still
/// selecting", and AppKit says nothing. The caret moves on the press, so
/// anything following it from the notification lagged the click.
final class SourceTextView: NSTextView {
    var onSelect: () -> Void = {}

    /// Told of ⌘L while the keyboard is in this view or in the selection
    /// prompt laid over it.
    var onPrompt: () -> Void = {}

    /// Told of a click in the text, before it is acted on.
    var onMouseDown: () -> Void = {}

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        onSelect()
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown()
        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command, event.charactersIgnoringModifiers == "l", hasKeyboard else {
            return super.performKeyEquivalent(with: event)
        }
        onPrompt()
        return true
    }

    /// Whether the keyboard is in this text or in something laid over its
    /// pane. Every view in a window is offered a key equivalent, so without
    /// this, ⌘L in the terminal would answer here.
    private var hasKeyboard: Bool {
        guard let responder = window?.firstResponder as? NSView, let pane = enclosingScrollView?.superview else {
            return false
        }
        return responder.isDescendant(of: pane)
    }
}
