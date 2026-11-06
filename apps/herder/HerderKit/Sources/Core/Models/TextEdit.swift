import Foundation

/// One change to a string: `replaced` in the old text became `length` new
/// characters. An insert replaces nothing; a delete adds nothing.
///
/// Offsets are UTF-16 code units, like ``SyntaxToken``.
public struct TextEdit: Equatable, Sendable {
    public let replaced: NSRange
    public let length: Int

    public init(replaced: NSRange, length: Int) {
        self.replaced = replaced
        self.length = length
    }

    var change: Int { length - replaced.length }
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
    public func applying(_ edit: TextEdit) -> [SyntaxToken] {
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

private extension SyntaxToken {
    func moved(by change: Int) -> SyntaxToken {
        spanning(range.location + change, NSMaxRange(range) + change)
    }

    func spanning(_ from: Int, _ to: Int) -> SyntaxToken {
        SyntaxToken(range: NSRange(location: from, length: to - from), kind: kind)
    }
}
