import AppKit
import Syntax
import Testing

@testable import EditorFeature

@Suite struct SyntaxAttributesTests {
    /// A kind with no row in the table falls back to the base attributes, which
    /// would read as "this grammar does not highlight that" rather than as a
    /// missing pairing. This is what makes the omission visible.
    @Test(arguments: SyntaxTokenKind.allCases)
    func everyKindHasAStyleOfItsOwn(kind: SyntaxTokenKind) {
        let attributes = SyntaxAttributes.attributes(for: kind)
        let colour = attributes[.foregroundColor] as? NSColor
        let base = SyntaxAttributes.base[.foregroundColor] as? NSColor

        #expect(colour != nil)
        #expect(colour != base, "\(kind) has no colour of its own")
    }

    @Test func everyStyleCarriesAFont() {
        for kind in SyntaxTokenKind.allCases {
            #expect(SyntaxAttributes.attributes(for: kind)[.font] as? NSFont != nil)
        }
        #expect(SyntaxAttributes.base[.font] as? NSFont != nil)
    }

    /// Comments are slanted as well as coloured, so they read as not-code
    /// before the colour registers.
    @Test func commentsAreItalic() throws {
        let font = try #require(SyntaxAttributes.attributes(for: .comment)[.font] as? NSFont)
        #expect(font.fontDescriptor.symbolicTraits.contains(.italic))
    }
}
