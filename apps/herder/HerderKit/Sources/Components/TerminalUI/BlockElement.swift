import CoreGraphics

/// The block elements, U+2580 to U+259F, as rectangles of a cell rather than
/// glyphs of a font.
///
/// A font draws `▀` inside its own ascent and descent, which is not the cell's
/// height, so a row of them is a broken line where a program meant a solid
/// edge: opencode closes its prompt box with one. Every terminal that draws
/// these as shapes does so for the same reason.
struct BlockElement {
    /// Parts of the unit cell, origin top left, each filled at its opacity.
    let parts: [(rect: CGRect, opacity: CGFloat)]

    init?(_ text: String) {
        guard text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first,
              (0x2580...0x259F).contains(scalar.value) else { return nil }
        parts = Self.parts(for: scalar.value)
    }

    private static func parts(for value: UInt32) -> [(rect: CGRect, opacity: CGFloat)] {
        func solid(_ rects: CGRect...) -> [(rect: CGRect, opacity: CGFloat)] { rects.map { ($0, 1) } }
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        let topLeft = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let topRight = CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        let bottomLeft = CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        let bottomRight = CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)

        switch value {
        case 0x2580: return solid(CGRect(x: 0, y: 0, width: 1, height: 0.5))
        case 0x2581...0x2588:
            // Lower one eighth up to the full block.
            let height = CGFloat(value - 0x2580) / 8
            return solid(CGRect(x: 0, y: 1 - height, width: 1, height: height))
        case 0x2589...0x258F:
            // Left seven eighths down to left one eighth.
            let width = CGFloat(0x2590 - value) / 8
            return solid(CGRect(x: 0, y: 0, width: width, height: 1))
        case 0x2590: return solid(CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        case 0x2591: return [(whole, 0.25)]
        case 0x2592: return [(whole, 0.5)]
        case 0x2593: return [(whole, 0.75)]
        case 0x2594: return solid(CGRect(x: 0, y: 0, width: 1, height: 1.0 / 8))
        case 0x2595: return solid(CGRect(x: 7.0 / 8, y: 0, width: 1.0 / 8, height: 1))
        case 0x2596: return solid(bottomLeft)
        case 0x2597: return solid(bottomRight)
        case 0x2598: return solid(topLeft)
        case 0x2599: return solid(topLeft, bottomLeft, bottomRight)
        case 0x259A: return solid(topLeft, bottomRight)
        case 0x259B: return solid(topLeft, topRight, bottomLeft)
        case 0x259C: return solid(topLeft, topRight, bottomRight)
        case 0x259D: return solid(topRight)
        case 0x259E: return solid(topRight, bottomLeft)
        default: return solid(topRight, bottomLeft, bottomRight)
        }
    }
}
