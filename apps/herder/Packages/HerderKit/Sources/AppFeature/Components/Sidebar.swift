import DesignSystem
import SwiftUI

/// Leading pane. Empty for now beyond its header. Internal: only `AppFeature`
/// uses it.
struct Sidebar: View {
    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader()
            Spacer(minLength: 0)
        }
    }
}

/// Header strip. The leading side is deliberately empty: the window hides its
/// title bar, so macOS draws the traffic lights over that space.
private struct SidebarHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            WolfMark()
        }
        .frame(height: Theme.Size.titleBar)
        .padding(.horizontal, Theme.Spacing.paneInset)
    }
}

#if DEBUG
#Preview {
    Sidebar()
        .frame(width: Theme.Size.sidebarWidth, height: 420)
        .paneBackground()
        .padding(Theme.Spacing.windowPadding)
        .background(Theme.Palette.window)
}
#endif
