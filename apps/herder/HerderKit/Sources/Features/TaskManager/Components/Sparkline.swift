import Core
import DesignSystem
import SwiftUI

/// The last minute of a tile's number, as a line over a faint fill.
///
/// Drawn from the oldest point to the newest, scaled between zero and the
/// largest value it has seen, so a flat line sits at the bottom and a spike
/// fills the height. With fewer than two points there is nothing to draw.
struct Sparkline: View {
    let history: MetricHistory
    var color: Color = Theme.Palette.accent

    var body: some View {
        GeometryReader { geometry in
            let points = self.points(in: geometry.size)
            if points.count > 1 {
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geometry.size.height))
                        for point in points { path.addLine(to: point) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geometry.size.height))
                        path.closeSubpath()
                    }
                    .fill(color.opacity(0.14))

                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    /// Time runs along the full width of a minute, so a window just opened
    /// draws at the right edge, as a chart that fills from the right does.
    private func points(in size: CGSize) -> [CGPoint] {
        guard let newest = history.points.last?.at else { return [] }
        let peak = max(history.points.map(\.value).max() ?? 0, .leastNonzeroMagnitude)
        return history.points.map { point in
            let age = newest.timeIntervalSince(point.at) / MetricHistory.window
            return CGPoint(
                x: size.width * (1 - age),
                y: size.height * (1 - point.value / peak)
            )
        }
    }
}
