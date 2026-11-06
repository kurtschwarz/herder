import AppKit
import Core
import DesignSystem
import SwiftUI

/// Turns token kinds into colours.
///
/// The one place that knows both what a token means and what it should look
/// like. `Core` emits kinds and no colours; `DesignSystem` holds colours and
/// no kinds. Keeping the pairing here means a grammar can be added without
/// touching either.
///
/// Colour only, because it is applied as a layout manager rendering attribute,
/// which TextKit keeps out of the text storage and so out of the undo stack. A
/// rendering attribute cannot change a font.
///
/// Built once. Making an `NSColor` is not free, and a thousand tokens a file is
/// ordinary.
enum SyntaxAttributes {
    /// What every character starts as, before any token is applied. Lives in
    /// the text storage, as the font and the typing attributes of the view.
    static let base: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: Theme.Size.code, weight: .regular),
        .foregroundColor: baseColour,
    ]

    /// The colour for a kind.
    static func colour(for kind: SyntaxTokenKind) -> NSColor {
        byKind[kind] ?? baseColour
    }

    private static let baseColour = NSColor(Theme.Palette.text)

    private static let byKind: [SyntaxTokenKind: NSColor] = [
        .comment: NSColor(Theme.Palette.Syntax.comment),
        .keyword: NSColor(Theme.Palette.Syntax.keyword),
        .operator: NSColor(Theme.Palette.Syntax.operator),
        .punctuation: NSColor(Theme.Palette.Syntax.punctuation),
        .string: NSColor(Theme.Palette.Syntax.string),
        .escape: NSColor(Theme.Palette.Syntax.escape),
        .number: NSColor(Theme.Palette.Syntax.number),
        .constant: NSColor(Theme.Palette.Syntax.constant),
        .function: NSColor(Theme.Palette.Syntax.function),
        .type: NSColor(Theme.Palette.Syntax.type),
        .constructor: NSColor(Theme.Palette.Syntax.constructor),
        .variable: NSColor(Theme.Palette.Syntax.variable),
        .property: NSColor(Theme.Palette.Syntax.property),
        .parameter: NSColor(Theme.Palette.Syntax.parameter),
        .attribute: NSColor(Theme.Palette.Syntax.attribute),
        .tag: NSColor(Theme.Palette.Syntax.tag),
        .namespace: NSColor(Theme.Palette.Syntax.namespace),
        .label: NSColor(Theme.Palette.Syntax.label),
    ]
}
