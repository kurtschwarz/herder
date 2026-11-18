import Core
import Foundation

/// A pointer at some lines of a file, in the form an agent reads: what the
/// selection prompt types into a session.
///
/// Whole lines only. A selection that starts or ends inside a line still
/// refers to all of it, and says so with ``isPartial``, so the prompt can be
/// honest about it. No columns.
struct CodeRef: Equatable {
    /// The lines the reference covers, counting from one.
    var lines: ClosedRange<Int>

    /// Whether the selection it came from started or ended inside a line.
    var isPartial: Bool

    /// Where the file is, as the agent will be told: below the worktree, else
    /// absolute.
    var path: String

    /// The text of those lines, when the file on disk does not have it. Line
    /// numbers read off a file that has unsaved edits would point at the wrong
    /// lines, so such a ref carries the lines themselves.
    var unsavedText: String?

    /// What the file's extension says it is written in, for the fence.
    var language: String

    var lineCount: Int { lines.count }

    init(
        file: PathKey,
        worktree: PathKey?,
        selection: SelectedLines,
        isUnsaved: Bool
    ) {
        lines = selection.lines
        isPartial = selection.isPartial
        if let worktree, !file.isUntitled, file.isInside(worktree), file != worktree {
            path = String(file.path.dropFirst(worktree.path.count).drop { $0 == "/" })
        } else {
            path = file.isUntitled ? file.name : file.path
        }
        unsavedText = isUnsaved || file.isUntitled ? selection.text : nil
        language = file.name.contains(".") ? URL(filePath: file.name).pathExtension : ""
    }

    private var range: String {
        lines.count == 1 ? "\(lines.lowerBound)" : "\(lines.lowerBound)-\(lines.upperBound)"
    }

    /// `@path#L10-12`, with the path quoted if it has a space in it. Or, for
    /// text that is not on disk, `path:10-12 (unsaved)` and the lines in a
    /// fenced block.
    var text: String {
        if let unsavedText {
            let body = unsavedText.hasSuffix("\n") ? String(unsavedText.dropLast()) : unsavedText
            return "\(path):\(range) (unsaved)\n```\(language)\n\(body)\n```"
        }
        let quoted = path.contains(where: \.isWhitespace) ? "\"\(path)\"" : path
        return "@\(quoted)#L\(range)"
    }
}

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
