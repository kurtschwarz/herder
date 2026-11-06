import SwiftUI

/// Builds a `Path` from SVG path data.
///
/// Deliberately minimal: it understands the absolute `M`, `L`, `C` and `Z`
/// commands that the shapes in this module use, and traps on anything else so an
/// unsupported path fails loudly at the point it is added rather than drawing
/// something subtly wrong.
///
/// Shapes are stored as data rather than an asset catalog because SwiftPM only
/// runs `actool` under Xcode. A catalog resource would resolve in the app and in
/// previews but not under `swift build`, which would make the two disagree.
/// `nonisolated` because this module defaults to `MainActor` but `Shape`'s
/// `path(in:)` requirement is not isolated.
nonisolated enum VectorPath {
    /// The path `data` describes, in the coordinates it is authored in.
    ///
    /// Parse once and keep the result: SwiftUI asks a shape for its path on
    /// every layout pass, and splitting a few thousand tokens each time was
    /// 50 MB of short-lived arrays every twelve seconds for the sidebar's wolf
    /// alone. ``fit(_:viewBox:in:)`` is the per-call part.
    static func parse(_ data: String) -> Path {
        var path = Path()
        var tokens = data.split(whereSeparator: { $0 == " " || $0 == "," || $0.isNewline })[...]

        func number() -> Double {
            guard let token = tokens.popFirst(), let value = Double(token) else {
                preconditionFailure("vector path: expected a number")
            }
            return value
        }

        func point() -> CGPoint {
            CGPoint(x: number(), y: number())
        }

        while let token = tokens.popFirst() {
            switch token {
            case "M":
                path.move(to: point())
            case "L":
                path.addLine(to: point())
            case "C":
                let control1 = point()
                let control2 = point()
                path.addCurve(to: point(), control1: control1, control2: control2)
            case "Z":
                path.closeSubpath()
            default:
                preconditionFailure("vector path: unsupported command '\(token)'")
            }
        }

        return path
    }

    /// Scales `path` from `viewBox` to fit `rect`, preserving aspect ratio and
    /// centring the result.
    static func fit(_ path: Path, viewBox: CGRect, in rect: CGRect) -> Path {
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let size = CGSize(width: viewBox.width * scale, height: viewBox.height * scale)
        let transform = CGAffineTransform(
            translationX: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )
        .scaledBy(x: scale, y: scale)
        .translatedBy(x: -viewBox.minX, y: -viewBox.minY)
        return path.applying(transform)
    }
}
