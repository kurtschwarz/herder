import Core
import Foundation
import Testing

@Suite struct SourceTextTests {
    let token = SyntaxToken(range: NSRange(location: 0, length: 3), kind: .keyword)

    @Test func textAloneIsPlain() {
        #expect(SourceText(text: "let x = 1").tokens.isEmpty)
    }

    /// The reason the two travel together: the editor compares what it last
    /// drew against what it has been given, and the same text arriving with
    /// different tokens has to count as a change.
    @Test func textAndTokensAreBothPartOfTheValue() {
        let plain = SourceText(text: "let x = 1")
        let highlighted = SourceText(text: "let x = 1", tokens: [token])

        #expect(plain != highlighted)
        #expect(highlighted == SourceText(text: "let x = 1", tokens: [token]))
        #expect(highlighted != SourceText(text: "let y = 2", tokens: [token]))
    }
}
