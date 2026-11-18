import Foundation

/// The lines a selection touches.
struct SelectedLines: Equatable {
    var lines: ClosedRange<Int>
    var isPartial: Bool

    /// Those lines' text, with the line break after the last one if it has one.
    var text: String

    /// The lines `range` touches in `text`. A caret is the line it is on, and
    /// a selection that ends right after a line break does not reach into the
    /// next line.
    init(of range: NSRange, in text: String) {
        let string = text as NSString
        let range = NSIntersectionRange(range, NSRange(location: 0, length: string.length))
        let end = range.length > 0 ? NSMaxRange(range) - 1 : range.location
        let first = string.lineRange(for: NSRange(location: range.location, length: 0))
        let last = string.lineRange(for: NSRange(location: end, length: 0))

        var contentsEnd = 0
        string.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: end, length: 0))

        var firstLine = 1
        var index = 0
        while index < first.location {
            index = NSMaxRange(string.lineRange(for: NSRange(location: index, length: 0)))
            firstLine += 1
        }
        var lastLine = firstLine
        index = first.location
        while NSMaxRange(string.lineRange(for: NSRange(location: index, length: 0))) < NSMaxRange(last) {
            index = NSMaxRange(string.lineRange(for: NSRange(location: index, length: 0)))
            lastLine += 1
        }

        lines = firstLine...lastLine
        let stop = NSMaxRange(range)
        isPartial = range.length > 0
            && (range.location != first.location || (stop != contentsEnd && stop != NSMaxRange(last)))
        self.text = string.substring(with: NSRange(location: first.location, length: NSMaxRange(last) - first.location))
    }
}
