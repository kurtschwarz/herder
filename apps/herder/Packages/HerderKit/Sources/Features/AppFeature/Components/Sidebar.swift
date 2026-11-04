import DesignSystem
import SwiftData
import SwiftUI
import WorkspacesFeature

/// Leading pane: the window's own header over the workspace list. Internal: only
/// `AppFeature` uses it.
struct Sidebar: View {
    let workspaces: WorkspacesModel

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader()
            WorkspacesView(model: workspaces)
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
    Sidebar(workspaces: AppModel.preview.workspaceList)
        .modelContainer(AppModel.previewContainer)
        .frame(width: Theme.Size.sidebarWidth, height: 420)
        .glassPaneBackground()
        .padding(Theme.Spacing.windowPadding)
        .background(Theme.Palette.window)
}
#endif
