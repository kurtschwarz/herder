import AppKit
import Core
import DesignSystem
import SwiftUI

/// Turns token kinds into text attributes.
///
/// The one place that knows both what a token means and what it should look
/// like. `Core` emits kinds and no colours; `DesignSystem` holds colours and
/// no kinds. Keeping the pairing here means a grammar can be added without
/// touching either.
///
/// Built once. Making an `NSFont` and an `NSColor` is not free, and a thousand
/// tokens a file is ordinary.
enum SyntaxAttributes {
    /// What every character starts as, before any token is applied.
    static let base: [NSAttributedString.Key: Any] = [
        .font: regular,
        .foregroundColor: NSColor(Theme.Palette.text),
    ]

    /// The attributes for a kind.
    static func attributes(for kind: SyntaxTokenKind) -> [NSAttributedString.Key: Any] {
        byKind[kind] ?? base
    }

    private static let regular = NSFont.monospacedSystemFont(ofSize: Theme.Size.code, weight: .regular)

    /// Comments are the one thing that reads better slanted: it marks them as
    /// not being code at a glance, before the colour registers.
    private static let italic = NSFontManager.shared.convert(regular, toHaveTrait: .italicFontMask)

    private static let byKind: [SyntaxTokenKind: [NSAttributedString.Key: Any]] = [
        .comment: [.font: italic, .foregroundColor: NSColor(Theme.Palette.Syntax.comment)],
        .keyword: colour(Theme.Palette.Syntax.keyword),
        .operator: colour(Theme.Palette.Syntax.operator),
        .punctuation: colour(Theme.Palette.Syntax.punctuation),
        .string: colour(Theme.Palette.Syntax.string),
        .escape: colour(Theme.Palette.Syntax.escape),
        .number: colour(Theme.Palette.Syntax.number),
        .constant: colour(Theme.Palette.Syntax.constant),
        .function: colour(Theme.Palette.Syntax.function),
        .type: colour(Theme.Palette.Syntax.type),
        .constructor: colour(Theme.Palette.Syntax.constructor),
        .variable: colour(Theme.Palette.Syntax.variable),
        .property: colour(Theme.Palette.Syntax.property),
        .parameter: colour(Theme.Palette.Syntax.parameter),
        .attribute: colour(Theme.Palette.Syntax.attribute),
        .tag: colour(Theme.Palette.Syntax.tag),
        .namespace: colour(Theme.Palette.Syntax.namespace),
        .label: colour(Theme.Palette.Syntax.label),
    ]

    private static func colour(_ colour: Color) -> [NSAttributedString.Key: Any] {
        [.font: regular, .foregroundColor: NSColor(colour)]
    }
}
