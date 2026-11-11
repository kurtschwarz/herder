import Foundation

/// A stretch of terminal text that may be a link.
public struct TerminalLinkCandidate: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case url(URL)
        case path(TerminalPathReference)
    }

    public var kind: Kind

    /// Where it is in the text searched, in UTF-16 units, to match `NSString`.
    public var range: Range<Int>

    public init(kind: Kind, range: Range<Int>) {
        self.kind = kind
        self.range = range
    }
}
