import DesignSystem
import SwiftUI

/// The settings window's content: a sidebar of panes beside the one chosen.
///
/// Draws no backdrop and configures no window. Those are the composition
/// root's, which gives this the same glass and chrome as the main window.
public struct SettingsView: View {
    @State private var selection: SettingsPane = .general

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection)
                .frame(width: Theme.Size.defaultSidebarWidth)
                .glassPaneBackground()
                .padding(Theme.Spacing.windowPadding)

            // Unpadded, unlike the sidebar, so a scrolling pane runs to the
            // window's edge and blurs out under its header there.
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general: GeneralSettings()
        }
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .frame(width: Theme.Size.settingsWindow.width, height: Theme.Size.settingsWindow.height)
        .background { WindowGlass() }
        .preferredColorScheme(.dark)
}
#endif
