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
    /// Scales `data` from `viewBox` to fit `rect`, preserving aspect ratio and
    /// centring the result.
    static func path(_ data: String, viewBox: CGRect, in rect: CGRect) -> Path {
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let size = CGSize(width: viewBox.width * scale, height: viewBox.height * scale)
        let origin = CGPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )

        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(
                x: origin.x + (x - viewBox.minX) * scale,
                y: origin.y + (y - viewBox.minY) * scale
            )
        }

        var path = Path()
        var tokens = data.split(whereSeparator: { $0 == " " || $0 == "," || $0.isNewline })[...]

        func number() -> Double {
            guard let token = tokens.popFirst(), let value = Double(token) else {
                preconditionFailure("vector path: expected a number")
            }
            return value
        }

        while let token = tokens.popFirst() {
            switch token {
            case "M":
                path.move(to: point(number(), number()))
            case "L":
                path.addLine(to: point(number(), number()))
            case "C":
                let control1 = point(number(), number())
                let control2 = point(number(), number())
                path.addCurve(to: point(number(), number()), control1: control1, control2: control2)
            case "Z":
                path.closeSubpath()
            default:
                preconditionFailure("vector path: unsupported command '\(token)'")
            }
        }

        return path
    }
}
