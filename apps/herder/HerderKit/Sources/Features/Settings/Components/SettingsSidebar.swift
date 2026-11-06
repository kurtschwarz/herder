import DesignSystem
import SwiftUI

/// The leading pane: the window's header strip over the list of panes, laid
/// out like the main window's sidebar so the traffic lights land in the same
/// place in both.
struct SettingsSidebar: View {
    @Binding var selection: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The leading side is the traffic lights'.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                WolfMark()
            }
            .frame(height: Theme.Size.titleBar)
            .padding(.horizontal, Theme.Spacing.paneInset)

            Text("Settings")
                .font(.headline)
                .foregroundStyle(Theme.Palette.text)
                .padding(.horizontal, Theme.Spacing.paneInset)
                .padding(.bottom, Theme.Spacing.normal)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsPane.allCases) { pane in
                    SettingsSidebarRow(pane: pane, isSelected: selection == pane) { selection = pane }
                }
            }
            .padding(.horizontal, Theme.Spacing.tight)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct SettingsSidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: Theme.Spacing.normal) {
                SettingsPaneIcon(pane: pane, size: Theme.Size.settingsIcon)

                Text(pane.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.normal)
            .padding(.vertical, Theme.Spacing.tight)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(isHovering || isSelected ? Theme.Palette.control : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
