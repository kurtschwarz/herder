import DesignSystem
import EditorFeature
import ExplorerFeature
import SwiftUI
import WorkspacesFeature

/// Root view. Owns the window layout and composes features; holds no feature logic.
///
/// Panes float on the window with a uniform inset and gap rather than sitting in a
/// `NavigationSplitView`, because the design has no divider and gives each pane its
/// own rounded surface.
public struct AppView: View {
    @State private var environment: AppEnvironment

    public init(environment: AppEnvironment) {
        _environment = State(initialValue: environment)
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.paneGap) {
            Sidebar(workspaces: environment.workspaceList)
                .frame(width: Theme.Size.sidebarWidth)
                .glassPaneBackground()

            EditorView(model: environment.editor, rootName: environment.workspaceList.selectedWorkspaceName)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ExplorerView(model: environment.explorer, rootName: environment.workspaceList.selectedWorkspaceName)
                .frame(width: Theme.Size.sidebarWidth)
                .glassPaneBackground()
        }
        // The sidebar owns the selection and the explorer must not import it,
        // so the plain URL crosses here.
        .task(id: environment.workspaceList.selectedWorktree) {
            // A file from the worktree before is stale, not preserved.
            environment.editor.close()
            await environment.explorer.setRoot(environment.workspaceList.selectedWorktree)
        }
        // Selection only ever opens. A file that goes from disk loses its
        // selection but not its pane: the editor keeps it, struck through.
        .task(id: environment.explorer.selected) {
            guard let file = environment.explorer.selected else { return }
            await environment.editor.open(file)
        }
        // The modal's scrim swallows clicks; this stops the keyboard reaching
        // what it covers.
        .disabled(environment.workspaceList.isModalPresented)
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
        .overlay { AddWorkspaceOverlay(model: environment.workspaceList) }
        .overlay { NewSessionOverlay(model: environment.workspaceList) }
        .preferredColorScheme(.dark)
    }
}

#if DEBUG
#Preview {
    AppView(environment: .preview)
        .frame(width: 980, height: 620)
        .modelContainer(AppEnvironment.previewContainer)
}
#endif
