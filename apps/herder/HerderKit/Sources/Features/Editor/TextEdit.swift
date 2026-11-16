import Core
import Foundation

/// One change to a string: `replaced` in the old text became `length` new
/// characters. An insert replaces nothing; a delete adds nothing.
///
/// Offsets are UTF-16 code units, like ``SyntaxToken``.
struct TextEdit: Equatable, Sendable {
    let replaced: NSRange
    let length: Int

    init(replaced: NSRange, length: Int) {
        self.replaced = replaced
        self.length = length
    }

    var change: Int { length - replaced.length }

    /// Where `range` sits once this edit has been made, widened to take in
    /// anything the edit cut into. Used to keep a span that has to be
    /// repainted pointing at the right text.
    func carrying(_ range: NSRange) -> NSRange {
        let start = replaced.location
        let end = NSMaxRange(replaced)
        func moved(_ offset: Int, keeping edge: Int) -> Int {
            if offset <= start { return offset }
            if offset >= end { return offset + change }
            return edge
        }
        let from = moved(range.location, keeping: start)
        let to = moved(NSMaxRange(range), keeping: start + length)
        return NSRange(location: from, length: max(0, to - from))
    }
}

extension [SyntaxToken] {
    /// Where these tokens sit in the text once `edit` has been made.
    ///
    /// A stopgap that keeps colour in place until the text is parsed again,
    /// not a substitute for parsing. Its rules:
    ///
    /// - Text typed or replaced *inside* a token belongs to it, so typing in a
    ///   string stays string-coloured.
    /// - Text typed at a token's start or end does not, so characters typed
    ///   after a closing quote do not turn the colour of the string.
    /// - Text deleted or replaced across a token's edge takes that part of the
    ///   token with it and leaves the rest.
    /// - Everything after the edit moves by the change in length.
    func applying(_ edit: TextEdit) -> [SyntaxToken] {
        let start = edit.replaced.location
        let end = NSMaxRange(edit.replaced)
        let change = edit.change

        var result: [SyntaxToken] = []
        result.reserveCapacity(count)
        for token in self {
            let from = token.range.location
            let to = NSMaxRange(token.range)

            if to <= start {
                result.append(token)
            } else if from >= end {
                result.append(token.moved(by: change))
            } else if from < start && end < to {
                result.append(token.spanning(from, to + change))
            } else {
                if from < start { result.append(token.spanning(from, start)) }
                if to > end { result.append(token.spanning(end + change, to + change)) }
            }
        }
        return result
    }
}

extension [SyntaxToken] {
    /// The smallest range of the text that has to be repainted to go from
    /// painting these tokens to painting `new`, or `nil` when they paint the
    /// same thing.
    ///
    /// Both runs must be positioned in the same text: shift the old one with
    /// ``applying(_:)`` first. Whatever the two share at the start and at the
    /// end is left out, so a keystroke that changes one token repaints one.
    func changedRange(to new: [SyntaxToken]) -> NSRange? {
        let shared = Swift.min(count, new.count)
        var head = 0
        while head < shared, self[head] == new[head] { head += 1 }
        if head == count && head == new.count { return nil }

        var tail = 0
        while tail < shared - head, self[count - 1 - tail] == new[new.count - 1 - tail] { tail += 1 }

        let differing = self[head..<(count - tail)] + new[head..<(new.count - tail)]
        guard
            let first = differing.map(\.range.location).min(),
            let last = differing.map({ NSMaxRange($0.range) }).max()
        else { return nil }
        return NSRange(location: first, length: last - first)
    }
}

private extension SyntaxToken {
    func moved(by change: Int) -> SyntaxToken {
        spanning(range.location + change, NSMaxRange(range) + change)
    }

    func spanning(_ from: Int, _ to: Int) -> SyntaxToken {
        SyntaxToken(range: NSRange(location: from, length: to - from), kind: kind)
    }
}
