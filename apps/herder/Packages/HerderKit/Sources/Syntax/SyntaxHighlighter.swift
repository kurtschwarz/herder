/// Finds the tokens in a file's text.
///
/// A protocol, not because there is a second implementation worth having, but
/// so the editor can be exercised without the parser: `NoSyntaxHighlighter`
/// turns highlighting off without a flag to read anywhere.
///
/// Not a `Client`: there is no disk, network, process or clock behind it. The
/// same text gives the same tokens every time, which is why tests can use the
/// real one.
public protocol SyntaxHighlighter: Sendable {
    /// Tokens for `contents`, empty when no grammar claims `fileName`.
    ///
    /// `fileName` may be a whole path; only its last component is looked at.
    /// It is needed as well as the contents because the file's name is the
    /// main evidence of what language it is in.
    ///
    /// `async` because parsing a megabyte is not something to do on the main
    /// actor. An implementation that wants a thread of its own marks itself
    /// `@concurrent`; the default isolation rules otherwise run it wherever it
    /// was called from.
    func tokens(in contents: String, ofFileNamed fileName: String) async -> [SyntaxToken]
}

/// Highlights nothing.
///
/// For previews and for tests that are about the editor rather than about
/// colour.
public struct NoSyntaxHighlighter: SyntaxHighlighter {
    public init() {}

    public func tokens(in contents: String, ofFileNamed fileName: String) async -> [SyntaxToken] {
        []
    }
}
