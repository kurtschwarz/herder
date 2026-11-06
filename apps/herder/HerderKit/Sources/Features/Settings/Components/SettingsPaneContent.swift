import DesignSystem
import SwiftUI

/// A pane's scrolling body under its pinned header.
///
/// The header is a scroll edge bar rather than a plain inset, so what scrolls
/// under it blurs into the glass instead of being cut off at a line.
struct SettingsPaneContent<Content: View>: View {
    let pane: SettingsPane
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.paneInset)
            .padding(.bottom, Theme.Spacing.section)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaBar(edge: .top, spacing: 0) { SettingsPaneHeader(pane: pane) }
    }
}

private struct SettingsPaneHeader: View {
    let pane: SettingsPane

    var body: some View {
        HStack(spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
            SettingsPaneIcon(pane: pane, size: Theme.Size.settingsHeaderIcon)

            Text(pane.title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.Palette.text)

            Spacer(minLength: 0)
        }
        // The same strip as the sidebar's header, so the title sits level
        // with the traffic lights.
        .frame(height: Theme.Size.titleBar)
        .padding(.top, Theme.Spacing.windowPadding)
        .padding(.bottom, Theme.Spacing.normal)
        .padding(.horizontal, Theme.Spacing.paneInset)
        // The edge effect blurs what passes under the header but keeps its
        // contrast, so the title sits on a wash that fades out at the seam
        // rather than ending on an edge.
        .background {
            LinearGradient(
                stops: [
                    .init(color: Theme.Palette.windowTint, location: 0),
                    .init(color: Theme.Palette.windowTint, location: 0.78),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
