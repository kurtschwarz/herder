import AppKit

/// An `NSTextView` that says when its selection moves, mid-click included.
///
/// `didChangeSelectionNotification` and the delegate are only told once the
/// mouse comes up: while the button is held the selection is "still
/// selecting", and AppKit says nothing. The caret moves on the press, so
/// anything following it from the notification lagged the click.
final class SourceTextView: NSTextView {
    var onSelect: () -> Void = {}

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        onSelect()
    }
}
