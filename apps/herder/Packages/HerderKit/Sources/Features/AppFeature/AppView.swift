import DesignSystem
import ExplorerFeature
import SwiftUI
import WorkspacesFeature

/// Root view. Owns the window layout and composes features; holds no feature logic.
///
/// Panes float on the window with a uniform inset and gap rather than sitting in a
/// `NavigationSplitView`, because the design has no divider and gives each pane its
/// own rounded surface.
public struct AppView: View {
    @State private var model: AppModel

    public init(model: AppModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.paneGap) {
            Sidebar(workspaces: model.workspaceList)
                .frame(width: Theme.Size.sidebarWidth)
                .glassPaneBackground()

            Detail()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ExplorerView(model: model.explorer)
                .frame(width: Theme.Size.sidebarWidth)
                .glassPaneBackground()
        }
        // The sidebar owns the selection and the explorer must not import it,
        // so the plain URL crosses here.
        .task(id: model.workspaceList.selectedWorktree) {
            await model.explorer.setRoot(model.workspaceList.selectedWorktree)
        }
        // The modal's scrim swallows clicks; this stops the keyboard reaching
        // what it covers.
        .disabled(model.workspaceList.isModalPresented)
        .padding(Theme.Spacing.windowPadding)
        .frame(minWidth: 960, minHeight: 460)
        .background { WindowGlass() }
        .background(WindowChrome())
        // The window draws no title bar, but SwiftUI still reserves a safe area
        // the height of one. Without this the panes start below the traffic
        // lights instead of around them.
        .ignoresSafeArea()
        // After the safe area is ignored, so the scrim covers the whole window,
        // title bar included.
        .overlay { AddWorkspaceOverlay(model: model.workspaceList) }
        .overlay { NewSessionOverlay(model: model.workspaceList) }
        .preferredColorScheme(.dark)
    }
}

#if DEBUG
#Preview {
    AppView(model: .preview)
        .frame(width: 980, height: 620)
        .modelContainer(AppModel.previewContainer)
}
#endif
