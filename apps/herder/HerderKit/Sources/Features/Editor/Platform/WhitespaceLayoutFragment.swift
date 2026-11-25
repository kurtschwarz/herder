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
    final class Glyphs {
        let space: NSTextLineFragment
        let tab: NSTextLineFragment
        let lineEnding: NSTextLineFragment

        init(attributes: [NSAttributedString.Key: Any]) {
            func line(_ kind: WhitespaceMarker.Kind) -> NSTextLineFragment {
                NSTextLineFragment(string: kind.glyph, attributes: attributes, range: NSRange(location: 0, length: 1))
            }
            space = line(.space)
            tab = line(.tab)
            lineEnding = line(.lineEnding)
        }

        func glyph(for kind: WhitespaceMarker.Kind) -> NSTextLineFragment {
            switch kind {
            case .space: space
            case .tab: tab
            case .lineEnding: lineEnding
            }
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
            bounds.size.width = max(bounds.width, end + glyphs.lineEnding.typographicBounds.width - bounds.minX)
        }
        return bounds
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        guard mode != .none, let glyphs else { return }
        for marker in markers() {
            glyphs.glyph(for: marker.kind).draw(
                at: CGPoint(x: point.x + marker.origin.x, y: point.y + marker.origin.y),
                in: context
            )
        }
    }

    /// Each marker and where its glyph's line starts, relative to this
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
                x += (width - glyphs.space.typographicBounds.width) / 2
            }
            result.append((marker.kind, CGPoint(x: bounds.minX + x, y: bounds.minY)))
        }
        // Only once there is a layout to measure: an empty answer before
        // that is not the answer.
        if !textLineFragments.isEmpty { placed = result }
        return result
    }
}
