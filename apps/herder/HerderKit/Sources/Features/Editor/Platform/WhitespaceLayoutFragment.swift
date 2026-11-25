import AppKit
import Core

/// A paragraph that draws its whitespace markers after its text.
///
/// Drawn by TextKit into the paragraph's own view, which it keeps and moves
/// as the text scrolls, so a marker costs nothing once it is on screen and an
/// edit redraws only the paragraph it touched. The markers are never
/// characters: copying, saving, the caret and the columns cannot see them.
nonisolated final class WhitespaceLayoutFragment: NSTextLayoutFragment {
    /// The three markers, laid out once and shared by every paragraph.
    ///
    /// Core Text lines rather than `NSTextLineFragment`s: one made outside a
    /// layout is never laid out, so it measures nothing and draws nothing.
    final class Glyphs {
        private let lines: [WhitespaceMarker.Kind: CTLine]

        init(font: NSFont, colour: NSColor) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour.cgColor,
            ]
            var lines: [WhitespaceMarker.Kind: CTLine] = [:]
            for kind in [WhitespaceMarker.Kind.space, .tab, .lineEnding] {
                lines[kind] = CTLineCreateWithAttributedString(NSAttributedString(string: kind.glyph, attributes: attributes))
            }
            self.lines = lines
        }

        func line(for kind: WhitespaceMarker.Kind) -> CTLine {
            lines[kind]!
        }

        func width(of kind: WhitespaceMarker.Kind) -> CGFloat {
            CGFloat(CTLineGetTypographicBounds(line(for: kind), nil, nil, nil))
        }
    }

    var mode = ShowWhitespace.none {
        didSet { if mode != oldValue { placed = nil } }
    }

    var glyphs: Glyphs?

    /// Where each marker goes, worked out on first draw and kept until the
    /// layout or the mode changes.
    private var placed: [(kind: WhitespaceMarker.Kind, origin: CGPoint)]?

    override func invalidateLayout() {
        super.invalidateLayout()
        placed = nil
    }

    /// Wide enough for a line ending's marker past the last character, in
    /// every mode, so changing the mode never needs a new layout.
    override var renderingSurfaceBounds: CGRect {
        var bounds = super.renderingSurfaceBounds
        guard let glyphs else { return bounds }
        for line in textLineFragments {
            let end = line.typographicBounds.minX + line.locationForCharacter(at: NSMaxRange(line.characterRange)).x
            bounds.size.width = max(bounds.width, end + glyphs.width(of: .lineEnding) - bounds.minX)
        }
        return bounds
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        guard mode != .none, let glyphs else { return }
        context.saveGState()
        defer { context.restoreGState() }
        // TextKit hands over a flipped context, and Core Text draws upright
        // only in an unflipped one.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for marker in markers() {
            context.textPosition = CGPoint(x: point.x + marker.origin.x, y: point.y + marker.origin.y)
            CTLineDraw(glyphs.line(for: marker.kind), context)
        }
    }

    /// Each marker and where its glyph's baseline starts, relative to this
    /// fragment, the coordinates `draw(at:in:)` is given its point in.
    func markers() -> [(kind: WhitespaceMarker.Kind, origin: CGPoint)] {
        if let placed { return placed }
        guard let glyphs, let text = textLineFragments.first?.attributedString.string as NSString? else { return [] }

        var result: [(kind: WhitespaceMarker.Kind, origin: CGPoint)] = []
        let found = WhitespaceMarker.find(in: text, touching: NSRange(location: 0, length: text.length), mode: mode)
        let lines = textLineFragments
        var index = 0
        for marker in found {
            // A line ending may lie past the last line's characters, so
            // the last line takes whatever no line before it holds.
            while index < lines.count - 1, marker.location >= NSMaxRange(lines[index].characterRange) {
                index += 1
            }
            let line = lines[index]
            let bounds = line.typographicBounds
            var x = line.locationForCharacter(at: marker.location).x
            if marker.kind == .space {
                let width = line.locationForCharacter(at: marker.location + 1).x - x
                x += (width - glyphs.width(of: .space)) / 2
            }
            result.append((marker.kind, CGPoint(x: bounds.minX + x, y: bounds.minY + line.glyphOrigin.y)))
        }
        // Only once there is a layout to measure: an empty answer before
        // that is not the answer.
        if !textLineFragments.isEmpty { placed = result }
        return result
    }
}
