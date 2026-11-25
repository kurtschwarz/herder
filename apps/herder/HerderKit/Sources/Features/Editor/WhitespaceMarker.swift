import Core
import Foundation

/// A character the editor marks, and where it is.
struct WhitespaceMarker: Equatable {
    enum Kind: Equatable {
        case space
        case tab
        /// Sits on the first character of the line ending, so `\r\n` is one.
        case lineEnding

        var glyph: String {
            switch self {
            case .space: "\u{00B7}"
            case .tab: "\u{2192}"
            case .lineEnding: "\u{00AC}"
            }
        }
    }

    let kind: Kind
    /// UTF-16 offset in the text.
    let location: Int

    /// The markers for the lines of `text` that touch `range`: all of each
    /// such line, because whether a space is trailing depends on what follows
    /// it.
    ///
    /// The last line gets no line-ending marker if the text does not end in
    /// one. In `trailing` mode there are no line-ending markers at all.
    static func find(in text: NSString, touching range: NSRange, mode: ShowWhitespace) -> [WhitespaceMarker] {
        guard mode != .none, text.length > 0 else { return [] }
        guard range.location < text.length else { return [] }
        var markers: [WhitespaceMarker] = []
        var next = text.lineRange(for: NSRange(location: range.location, length: 0)).location
        let end = min(max(NSMaxRange(range), range.location + 1), text.length)
        while next < end {
            var start = 0, lineEnd = 0, contentsEnd = 0
            text.getLineStart(&start, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: next, length: 0))

            // Where the run of spaces and tabs that ends the line begins.
            var trailing = contentsEnd
            while trailing > start, isBlank(text.character(at: trailing - 1)) { trailing -= 1 }

            for offset in start..<contentsEnd {
                let character = text.character(at: offset)
                guard isBlank(character), mode == .all || offset >= trailing else { continue }
                markers.append(WhitespaceMarker(kind: character == 0x09 ? .tab : .space, location: offset))
            }
            if mode == .all, lineEnd > contentsEnd {
                markers.append(WhitespaceMarker(kind: .lineEnding, location: contentsEnd))
            }
            next = lineEnd
        }
        return markers
    }

    private static func isBlank(_ character: unichar) -> Bool {
        character == 0x20 || character == 0x09
    }
}
