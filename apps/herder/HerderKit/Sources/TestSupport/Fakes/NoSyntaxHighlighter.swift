#if DEBUG
import Core

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
#endif
