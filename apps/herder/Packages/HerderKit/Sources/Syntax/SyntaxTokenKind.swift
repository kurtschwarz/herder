/// What a span of source means, as far as colouring it goes.
///
/// Semantic, not visual: nothing here names a colour. `DesignSystem` holds the
/// colours and `EditorFeature` pairs the two, so retheming the editor touches
/// neither this module nor any grammar.
///
/// Deliberately coarse. Every case has to be given a colour a reader can tell
/// apart from the others, which runs out long before the hundreds of capture
/// names tree-sitter grammars use between them.
///
/// Raw values match `Kind` in `packages/syntax/src/kind.rs`, and
/// `SyntaxTests` asserts the two have the same number of cases.
public enum SyntaxTokenKind: UInt32, Sendable, CaseIterable {
    case comment = 0
    case keyword = 1
    case `operator` = 2
    case punctuation = 3
    case string = 4
    case escape = 5
    case number = 6
    case constant = 7
    case function = 8
    case type = 9
    case constructor = 10
    case variable = 11
    case property = 12
    case parameter = 13
    case attribute = 14
    case tag = 15
    case namespace = 16
    case label = 17
}
