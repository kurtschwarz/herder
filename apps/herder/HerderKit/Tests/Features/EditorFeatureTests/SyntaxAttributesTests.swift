import AppKit
import Core
import Testing

@testable import EditorFeature

@Suite struct SyntaxAttributesTests {
    /// A kind with no row in the table falls back to the base colour, which
    /// would read as "this grammar does not highlight that" rather than as a
    /// missing pairing. This is what makes the omission visible.
    @Test(arguments: SyntaxTokenKind.allCases)
    func everyKindHasAColourOfItsOwn(kind: SyntaxTokenKind) {
        let base = SyntaxAttributes.base[.foregroundColor] as? NSColor

        #expect(SyntaxAttributes.colour(for: kind) != base, "\(kind) has no colour of its own")
    }

    @Test func theBaseCarriesAFont() {
        #expect(SyntaxAttributes.base[.font] as? NSFont != nil)
    }
}
