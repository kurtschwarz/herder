import DesignSystem
import SwiftUI

/// A pane's coloured tile: its gradient, a lit rim along the top, and its glyph
/// in white. The same tile at two sizes, in the sidebar and at the pane's head.
struct SettingsPaneIcon: View {
    let pane: SettingsPane
    let size: CGFloat

    /// Proportional, so the large tile is the small one scaled rather than a
    /// squarer shape.
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
    }

    var body: some View {
        ZStack {
            shape
                .fill(pane.tint)
                .shadow(color: Theme.Shadow.tileColor, radius: Theme.Shadow.tileRadius, y: Theme.Shadow.tileOffset)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [Theme.Palette.tileHighlight, .clear], startPoint: .top, endPoint: .center),
                        lineWidth: 1
                    )
                }

            PhIcon(pane.glyph, size: size * 0.6)
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
