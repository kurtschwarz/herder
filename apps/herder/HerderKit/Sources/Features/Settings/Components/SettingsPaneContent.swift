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

    @Environment(\.settingsFile) private var file

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.normal) {
            HStack(spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
                SettingsPaneIcon(pane: pane, size: Theme.Size.settingsHeaderIcon)

                Text(pane.title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.Palette.text)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)

                if let file {
                    HoverIconButton(icon: Ph.fileCode, help: "Open settings.json", action: file.open)
                }
            }
            // The same strip as the sidebar's header, so the title sits level
            // with the traffic lights.
            .frame(height: Theme.Size.titleBar)

            if let file, let problem = file.problem {
                SettingsFileProblem(problem: problem, open: file.open)
            }
        }
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
    }
}

/// Says the file cannot be used and why, without stopping anything: the
/// settings in force are the last good ones.
private struct SettingsFileProblem: View {
    let problem: String
    let open: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.normal) {
            PhIcon(Ph.warningFill, size: 12)
                .foregroundStyle(Theme.Palette.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("settings.json can\u{2019}t be used, so the last good settings are in force. Changes made here aren\u{2019}t saved until it\u{2019}s fixed.")
                    .foregroundStyle(Theme.Palette.text)
                Text(problem)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .textSelection(.enabled)
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Open in editor", action: open)
                .buttonStyle(.link)
        }
        .padding(Theme.Spacing.normal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fieldGroupSurface()
    }
}
