import Core
import DesignSystem
import EditorFeature
import FileTreeFeature
import RepositoriesFeature
import SwiftUI

/// Root view. Owns the window layout and composes features; holds no feature logic.
///
/// Panes float on the window with a uniform inset and gap rather than sitting in a
/// `NavigationSplitView`, because the design has no divider and gives each pane its
/// own rounded surface.
public struct AppView: View {
    @State private var environment: AppEnvironment

    /// This window's own state. `@State`, so a second window gets a second one
    /// and the two can show different checkouts.
    @State private var window = WindowModel()

    /// Which workspace this window was showing, kept by the system per window
    /// rather than by the app globally. The path, because `WorkspaceID` is a
    /// path and `@SceneStorage` takes the primitives.
    @SceneStorage("activeWorkspacePath") private var activeWorkspacePath: String?

    public init(environment: AppEnvironment) {
        _environment = State(initialValue: environment)
    }

    /// The workspace this window is showing, resolved from the id. `nil` until
    /// the task below has opened it, and again once its folder goes away.
    private var activeWorkspace: Workspace? {
        guard let id = window.activeWorkspaceID else { return nil }
        return environment.worktrees.workspace(for: id)
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.paneGap) {
            Sidebar(model: environment.repositoryList, store: environment.repositories)
                .frame(width: Theme.Size.sidebarWidth)
                .glassPaneBackground()

            EditorView(model: environment.editor, rootName: activeWorkspaceName)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            FileTreeView(model: environment.fileTree, rootName: activeWorkspaceName)
                .frame(width: Theme.Size.sidebarWidth)
                .glassPaneBackground()
        }
        // Features read the workspace; they never ask which one is active.
        .environment(activeWorkspace)
        // And they ask for a different one through here, rather than reaching
        // for a window they cannot see.
        .environment(\.openWorkspace, OpenWorkspaceAction { window.activate($0) })
        // Restores what this window was showing. Once, on appear: after that
        // the window is the source of truth and the storage follows it.
        .task {
            if window.activeWorkspaceID == nil, let path = activeWorkspacePath {
                window.activate(WorkspaceID(PathKey(canonical: path)))
            }
        }
        .onChange(of: window.activeWorkspaceID) { _, id in
            activeWorkspacePath = id?.root.path
        }
        // Switching workspaces is this, and only this: the id changed, so open
        // what it names. Nothing else is torn down.
        .task(id: window.activeWorkspaceID) {
            // A file from the worktree before is stale, not preserved.
            environment.editor.close()
            await environment.fileTree.setRoot(window.activeWorkspaceID?.url)
        }
        // Tells the registry what this window is showing, which is what
        // decides whether that workspace drains. Idempotent, so saying it
        // again on every change is the whole protocol.
        .onChange(of: window.activeWorkspaceID, initial: true) { _, id in
            environment.worktrees.display(id, from: window)
        }
        .onDisappear {
            environment.worktrees.stopDisplaying(from: window)
        }
        // A worktree removed in a terminal takes its window's selection with
        // it, and the workspace with it: there is nothing left to keep open.
        // The workspace marks itself unavailable when its folder goes, so this
        // is the one place that has to notice.
        .onChange(of: activeWorkspace?.isAvailable) { _, isAvailable in
            guard isAvailable == false, let id = window.activeWorkspaceID else { return }
            window.activate(nil)
            Task { await environment.worktrees.close(id) }
        }
        // Selection only ever opens. A file that goes from disk loses its
        // selection but not its pane: the editor keeps it, struck through.
        .task(id: environment.fileTree.selected) {
            guard let file = environment.fileTree.selected else { return }
            await environment.editor.open(file)
        }
        // The modal's scrim swallows clicks; this stops the keyboard reaching
        // what it covers.
        .disabled(environment.repositoryList.isModalPresented)
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
        .overlay { AddRepositoryOverlay(model: environment.repositoryList) }
        .overlay { NewSessionOverlay(model: environment.repositoryList) }
        .preferredColorScheme(.dark)
    }

    /// What the panes call the checkout they are showing: the workspace's name,
    /// not the worktree folder's, which is often `main` and says nothing about
    /// what it belongs to.
    private var activeWorkspaceName: String? {
        guard let url = window.activeWorkspaceID?.url else { return nil }
        return environment.repositoryList.nameOfRepository(holding: url)
    }
}

#if DEBUG
#Preview {
    AppView(environment: .preview)
        .frame(width: 980, height: 620)
}
#endif
