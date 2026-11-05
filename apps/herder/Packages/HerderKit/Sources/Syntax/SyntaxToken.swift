import Foundation

/// A span of source to paint, and what it is.
///
/// `range` is in UTF-16 code units, which is what `NSTextStorage` indexes in,
/// so a token goes straight to `addAttributes(_:range:)` with no conversion.
/// Tree-sitter counts bytes; the crate converts before handing them over,
/// because a conversion a caller has to remember is one a caller will forget.
public struct SyntaxToken: Equatable, Sendable {
    public let range: NSRange
    public let kind: SyntaxTokenKind

    public init(range: NSRange, kind: SyntaxTokenKind) {
        self.range = range
        self.kind = kind
    }
}
