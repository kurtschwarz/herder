/// A file's text together with the tokens found in it.
///
/// One value rather than two properties, so the pair cannot come apart. Tokens
/// are offsets into a particular string: hand them out beside a newer one and
/// the colours land on the wrong characters. Keeping them together makes that
/// unrepresentable instead of merely unlikely.
public struct SourceText: Equatable, Sendable {
    public let text: String

    /// Ordered, non-overlapping, and covering only what needs painting. Empty
    /// for a file no grammar claims.
    public let tokens: [SyntaxToken]

    public init(text: String, tokens: [SyntaxToken] = []) {
        self.text = text
        self.tokens = tokens
    }
}
