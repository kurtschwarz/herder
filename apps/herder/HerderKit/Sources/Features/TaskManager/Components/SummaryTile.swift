import Core
import DesignSystem
import SwiftUI

/// One of the four tiles along the top: a label, a big number, what it is a
/// share of, and a sparkline of the last minute where it has one.
struct SummaryTile<Detail: View>: View {
    let title: String
    let value: String
    let caption: String
    var history: MetricHistory?
    var color: Color = Theme.Palette.accent
    @ViewBuilder var detail: Detail

    private var captionText: some View {
        Text(caption)
            .font(.system(size: 12))
            .foregroundStyle(Theme.Palette.secondaryText)
            .lineLimit(1)
            .fixedSize()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(Theme.Palette.tertiaryText)

            Text(value)
                .font(.system(size: 26, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.text)

            // Side by side when they fit, else the detail over the caption.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.tight) { detail; captionText }
                VStack(alignment: .leading, spacing: 2) { detail; captionText }
            }

            if let history {
                Sparkline(history: history, color: color)
                    .frame(height: 28)
                    .padding(.top, Theme.Spacing.tight)
            }
        }
        .padding(Theme.Spacing.loose)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fieldGroupSurface()
    }
}

extension SummaryTile where Detail == EmptyView {
    init(title: String, value: String, caption: String, history: MetricHistory? = nil, color: Color = Theme.Palette.accent) {
        self.init(title: title, value: value, caption: caption, history: history, color: color) { EmptyView() }
    }
}
