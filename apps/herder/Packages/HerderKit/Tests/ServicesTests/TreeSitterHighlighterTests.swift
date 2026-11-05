import Core
import Foundation
import Services
import TestSupport
import Testing

/// Covers the boundary, not the grammars. What each grammar produces is tested
/// in `packages/syntax-highlighter`, where a failure says which capture went wrong; these
/// check that the two sides agree on offsets, kinds and ownership.
@Suite struct TreeSitterHighlighterTests {
    let highlighter = TreeSitterHighlighter()

    /// The text a token covers, by its own range.
    func text(_ token: SyntaxToken, of source: String) -> String {
        let string = source as NSString
        return string.substring(with: token.range)
    }

    @Test func aKnownFileComesBackWithTokens() async {
        let source = "// a note\nlet name = \"Herder\"\n"
        let tokens = await highlighter.tokens(in: source, ofFileNamed: "AppModel.swift")

        #expect(!tokens.isEmpty)
        #expect(tokens.contains { $0.kind == .comment })
        #expect(tokens.contains { $0.kind == .keyword })
        #expect(tokens.contains { $0.kind == .string })
    }

    @Test func aTokenCoversExactlyTheTextItStyles() async {
        let source = "let name = \"Herder\"\n"
        let tokens = await highlighter.tokens(in: source, ofFileNamed: "A.swift")

        let string = try? #require(tokens.first { $0.kind == .string })
        #expect(string.map { text($0, of: source) } == "\"Herder\"")
    }

    /// The reason the crate converts offsets before handing them over. Byte
    /// offsets would put this string two units to the right of where it is.
    @Test func offsetsAreUTF16SoTextAfterAnEmojiIsStillRight() async {
        let source = "// 🐺🐺\nlet name = \"Herder\"\n"
        let tokens = await highlighter.tokens(in: source, ofFileNamed: "A.swift")

        let string = try? #require(tokens.first { $0.kind == .string })
        #expect(string.map { text($0, of: source) } == "\"Herder\"")
    }

    @Test func aFileNoGrammarClaimsComesBackEmpty() async {
        let tokens = await highlighter.tokens(in: "just words\n", ofFileNamed: "notes.txt")
        #expect(tokens.isEmpty)
    }

    @Test func anEmptyFileComesBackEmpty() async {
        #expect(await highlighter.tokens(in: "", ofFileNamed: "A.swift").isEmpty)
        #expect(await highlighter.tokens(in: "", ofFileNamed: "").isEmpty)
    }

    @Test func aPathIsAcceptedWhereANameIs() async {
        let source = "let x = 1\n"
        let byName = await highlighter.tokens(in: source, ofFileNamed: "A.swift")
        let byPath = await highlighter.tokens(in: source, ofFileNamed: "/code/api/Sources/A.swift")
        #expect(byName == byPath)
        #expect(!byName.isEmpty)
    }

    @Test func tokensAreOrderedAndFitInsideTheText() async {
        let source = String(repeating: "// note\nlet x = 1\n", count: 200)
        let tokens = await highlighter.tokens(in: source, ofFileNamed: "A.swift")
        let length = (source as NSString).length

        #expect(tokens.count > 100)
        for token in tokens {
            #expect(token.range.length > 0)
            #expect(NSMaxRange(token.range) <= length)
        }
        for (earlier, later) in zip(tokens, tokens.dropFirst()) {
            #expect(NSMaxRange(earlier.range) <= later.range.location)
        }
    }

    /// Runs the same file through many times. A token buffer that was freed
    /// twice, or not at all, shows up here rather than as an occasional crash
    /// in front of a reader.
    @Test func repeatedCallsAgreeAndDoNotLeak() async {
        let source = "// note\nstruct A { let b: Int }\n"
        let first = await highlighter.tokens(in: source, ofFileNamed: "A.swift")
        for _ in 0..<200 {
            #expect(await highlighter.tokens(in: source, ofFileNamed: "A.swift") == first)
        }
    }

    @Test func theSameHighlighterIsUsableFromManyTasksAtOnce() async {
        let source = "// note\nlet x = 1\n"
        let expected = await highlighter.tokens(in: source, ofFileNamed: "A.swift")

        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<32 {
                group.addTask { await self.highlighter.tokens(in: source, ofFileNamed: "A.swift") == expected }
            }
            for await matched in group { #expect(matched) }
        }
    }

    @Test func noSyntaxHighlighterFindsNothingInAFileItWould() async {
        let tokens = await NoSyntaxHighlighter().tokens(in: "let x = 1\n", ofFileNamed: "A.swift")
        #expect(tokens.isEmpty)
    }

    /// The one thing neither side can check alone. A kind added to the crate
    /// and not to `SyntaxTokenKind` would make `SyntaxToken.init` drop every
    /// token carrying it, silently.
    @Test func everyKindTheCrateDefinesHasACaseHere() {
        #expect(SyntaxTokenKind.allCases.count == TreeSitterHighlighter.engineKindCount)
        #expect(SyntaxTokenKind.allCases.map(\.rawValue) == Array(0..<UInt32(SyntaxTokenKind.allCases.count)))
    }

    /// Warming only moves work earlier: the answers must be identical either
    /// side of it, and a second call must be harmless.
    @Test func warmingChangesNoAnswer() async {
        let source = "// note\nlet x = 1\n"
        let cold = await highlighter.tokens(in: source, ofFileNamed: "A.swift")

        await TreeSitterHighlighter.warmUp()
        await TreeSitterHighlighter.warmUp()

        #expect(await highlighter.tokens(in: source, ofFileNamed: "A.swift") == cold)
        #expect(!cold.isEmpty)
    }

    @Test func thereAreGrammarsLinkedIn() {
        #expect(TreeSitterHighlighter.engineLanguageCount > 10)
    }
}
