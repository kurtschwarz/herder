import Foundation
import HerderSyntaxFFI

/// The real highlighter: tree-sitter, through the `herder-syntax` crate.
///
/// The grammars, the queries and the table matching a file to a language all
/// live in `packages/syntax-highlighter`. Adding a language is a dependency in its
/// `Cargo.toml` and a row in its `LANGUAGES` — nothing here changes, and
/// nothing above here can tell.
///
/// Stateless, so no cache to invalidate and nothing to keep alive. The crate
/// keeps its own compiled queries for the life of the process.
public struct TreeSitterHighlighter: SyntaxHighlighter {
    public init() {}

    /// `@concurrent` on purpose. With `NonisolatedNonsendingByDefault` a plain
    /// `nonisolated` function runs on whichever actor called it, which for this
    /// one would be the main actor: the editor would stop redrawing while a
    /// file was parsed. This asks for the global executor instead.
    @concurrent
    public func tokens(in contents: String, ofFileNamed fileName: String) async -> [SyntaxToken] {
        // `withUTF8` lends the string's own bytes when it has them, which is
        // the point: a megabyte of source should not be copied to be read.
        var fileName = fileName
        var contents = contents
        return fileName.withUTF8 { name in
            contents.withUTF8 { source in
                let language = hdr_language_for(name.baseAddress, name.count, source.baseAddress, source.count)
                guard language != HDR_LANGUAGE_NONE else { return [] }

                let run = hdr_highlight(language, source.baseAddress, source.count)
                defer { hdr_tokens_free(run) }
                guard let tokens = run.tokens else { return [] }

                // Copied out before the deferred free, and before returning to
                // a caller that may be on another thread: the buffer belongs to
                // Rust and is not `Sendable`.
                return UnsafeBufferPointer(start: tokens, count: run.count)
                    .compactMap(SyntaxToken.init)
            }
        }
    }
}

extension TreeSitterHighlighter {
    /// Compiles every grammar's queries, so the first file opened does not pay
    /// for it.
    ///
    /// Worth calling, and worth calling early. Highlighting a file is a
    /// fraction of a millisecond; compiling the queries for one language is up
    /// to a quarter of a second, because the work scales with the size of the
    /// grammar rather than of the query. Left to happen on demand, that lands
    /// between a reader clicking a file and the file appearing.
    ///
    /// Blocking, and `@concurrent` for the same reason as `tokens`: it must not
    /// run on whichever actor called it.
    @concurrent
    public static func warmUp() async {
        hdr_warm()
    }

    /// How many kinds the crate defines. `SyntaxTests` checks it against
    /// `SyntaxTokenKind`, so a kind added on one side and not the other fails a
    /// test rather than painting an unknown colour.
    public static var engineKindCount: Int { Int(hdr_kind_count()) }

    /// How many grammars are built in. For tests and diagnostics.
    public static var engineLanguageCount: Int { Int(hdr_language_count()) }
}

extension SyntaxToken {
    /// `nil` for a kind this build of the app does not know, which means the
    /// crate and `SyntaxTokenKind` have drifted apart. Dropping the token
    /// leaves that span plain rather than crashing a reader's editor over it.
    init?(_ raw: HdrToken) {
        guard let kind = SyntaxTokenKind(rawValue: raw.kind), raw.start < raw.end else { return nil }
        self.init(
            range: NSRange(location: Int(raw.start), length: Int(raw.end - raw.start)),
            kind: kind
        )
    }
}
