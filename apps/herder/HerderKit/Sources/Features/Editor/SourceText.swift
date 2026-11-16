import Core

/// A file's text together with the tokens found in it.
///
/// One value rather than two properties, so the pair cannot come apart. Tokens
/// are offsets into a particular string: hand them out beside a newer one and
/// the colours land on the wrong characters. Keeping them together makes that
/// unrepresentable instead of merely unlikely.
struct SourceText: Equatable, Sendable {
    let text: String

    /// Ordered, non-overlapping, and covering only what needs painting. Empty
    /// for a file no grammar claims.
    let tokens: [SyntaxToken]

    init(text: String, tokens: [SyntaxToken] = []) {
        self.text = text
        self.tokens = tokens
    }
}
