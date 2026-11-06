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

    /// This window's own state and models, once it has claimed them. `@State`,
    /// so a second window gets a second one and the two can show different
    /// checkouts. `nil` for the moment between appearing and learning who it is.
    @State private var window: WindowEnvironment?

    /// What names this window across launches, kept by the system per scene.
    /// All it holds: everything else about the window is in its snapshot, which
    /// is found by this. The system only returns it when it restores the scene,
    /// and ``AppEnvironment/claimWindow(id:)`` covers the case where it does not.
    @SceneStorage("windowID") private var storedID: String?

    public init(environment: AppEnvironment) {
        _environment = State(initialValue: environment)
    }

    public var body: some View {
        Group {
            if let window {
                WindowView(window: window, environment: environment)
            }
        }
        // Above what the panes need (two minimum panes, the editor's floor, the
        // padding and the gaps): this is the smallest window worth showing, not
        // the smallest the layout survives.
        .frame(minWidth: 960, minHeight: 460)
        .background { WindowGlass() }
        .background(
            WindowChrome(
                onClose: { close() },
                unsavedFiles: { window?.editor.unsavedFiles ?? [] },
                saveAll: { await window?.editor.saveAll() ?? true }
            )
        )
        // After the backgrounds, so the glass runs under the title bar too.
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        // Once, on appear. Waits for the app to start, which is where the
        // folder access a workspace needs is taken.
        .task {
            guard window == nil else { return }
            let claimed = await environment.claimWindow(id: storedID.flatMap(UUID.init(uuidString:)))
            storedID = claimed.id.uuidString
            window = claimed
            await claimed.reopenHeldWorkspaces()
        }
    }

    private func close() {
        guard let window else { return }
        Task { await environment.close(window) }
    }
}

/// A window once it knows who it is.
private struct WindowView: View {
    let window: WindowEnvironment
    let environment: AppEnvironment

    /// What the three panes share, once the gaps between them are taken off.
    /// Zero until the first layout reports, which the clamp reads as "no room",
    /// so the panes sit at their minimum for that one frame.
    @State private var availableWidth: CGFloat = 0

    private let limits = PaneWidths.Limits(
        defaultWidth: Theme.Size.defaultSidebarWidth,
        minimumPane: Theme.Size.minSidebarWidth,
        minimumEditor: Theme.Size.minEditorWidth
    )

    var body: some View {
        let widths = window.paneWidths.resolved(in: availableWidth, limits: limits)

        // No spacing: the gaps between panes are the resize handles.
        HStack(spacing: 0) {
            Sidebar(model: window.repositoryList)
                .frame(width: widths.leading)
                .glassPaneBackground()

            ResizeHandle(
                widens: .trailing,
                width: widths.leading,
                onResize: { resize(.leading, to: $0) },
                onCommit: { window.commitPaneWidths() },
                onReset: { reset(.leading) }
            )

            VStack(spacing: 0) {
                EditorView(model: window.editor, rootName: activeWorkspaceName)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                StatusBar {
                    if let checkout = window.activeWorkspace?.checkout {
                        CheckoutLabel(checkout)
                    }
                } trailing: {
                    EditorFileStatus(model: window.editor)
                }
            }

            ResizeHandle(
                widens: .leading,
                width: widths.trailing,
                onResize: { resize(.trailing, to: $0) },
                onCommit: { window.commitPaneWidths() },
                onReset: { reset(.trailing) }
            )

            FileTreeView(model: window.fileTree, rootName: activeWorkspaceName)
                .frame(width: widths.trailing)
                .glassPaneBackground()
        }
        // Read, not laid out by: a `GeometryReader` here would become the root
        // of the layout and change how the panes size themselves.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width - 2 * Theme.Spacing.paneGap
        } action: {
            availableWidth = $0
        }
        // Features read the workspace; they never ask which one is active.
        .environment(window.activeWorkspace)
        // And they ask for a different one through here, rather than reaching
        // for a window they cannot see.
        .environment(\.openWorkspace, OpenWorkspaceAction { window.activate($0) })
        // Switching workspaces is this, and only this: the id changed, so open
        // what it names. Nothing else is torn down.
        .task(id: window.activeWorkspaceID) { await window.showActiveWorkspace() }
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
        .onChange(of: window.activeWorkspace?.isAvailable) { _, isAvailable in
            guard isAvailable == false, let id = window.activeWorkspaceID else { return }
            Task { await window.forget(id) }
        }
        .task(id: window.fileTree.selected) { await window.openSelectedFile() }
        .onChange(of: window.editor.file) { _, _ in window.followShownFile() }
        // The modal's scrim swallows clicks; this stops the keyboard reaching
        // what it covers.
        .disabled(window.repositoryList.isModalPresented)
        .padding(Theme.Spacing.windowPadding)
        // The window draws no title bar, but SwiftUI still reserves a safe area
        // the height of one. Without this the panes start below the traffic
        // lights instead of around them.
        .ignoresSafeArea()
        // After the safe area is ignored, so the scrim covers the whole window,
        // title bar included.
        .overlay { AddRepositoryOverlay(model: window.repositoryList) }
        .overlay { NewSessionOverlay(model: window.repositoryList) }
        // Where ⇧⌘N finds the window it should open the modal in.
        .focusedSceneValue(\.beginAddingRepository) { window.beginAddingRepository() }
        .modifier(EditorCommandValues(editor: window.editor))
    }

    private func resize(_ side: PaneWidths.Side, to proposed: CGFloat) {
        window.paneWidths = window.paneWidths.setting(side, to: proposed, in: availableWidth, limits: limits)
    }

    /// Animated, unlike the drag: the jump back is one the eye needs help
    /// following, where a drag has to track the pointer exactly.
    private func reset(_ side: PaneWidths.Side) {
        withAnimation(.easeOut(duration: 0.15)) {
            window.paneWidths = window.paneWidths.resetting(side)
        }
        window.commitPaneWidths()
    }

    /// What the panes call the checkout they are showing: the workspace's name,
    /// not the worktree folder's, which is often `main` and says nothing about
    /// what it belongs to.
    private var activeWorkspaceName: String? {
        guard let url = window.activeWorkspaceID?.url else { return nil }
        return window.repositoryList.nameOfRepository(holding: url)
    }
}

/// What the menu commands act on in this window: each is `nil` when it would do
/// nothing. Apart from ``WindowView`` because the one expression was too much
/// for the type checker.
private struct EditorCommandValues: ViewModifier {
    let editor: EditorModel

    func body(content: Content) -> some View {
        content
            // `nil` rather than a disabled-looking closure: an item with no action
            // is the one AppKit skips, which is what lets ⌘W reach the window's
            // own Close when there are no tabs. See ``AppCommands``.
            .focusedSceneValue(
                \.closeEditorTab,
                editor.tabs.isEmpty ? nil : { Task { await editor.closeActiveTab() } }
            )
            .focusedSceneValue(
                \.saveEditorFile,
                editor.canSave ? { Task { await editor.save() } } : nil
            )
            .focusedSceneValue(
                \.selectPreviousEditorTab,
                editor.tabs.count > 1 ? { Task { await editor.selectPreviousTab() } } : nil
            )
            .focusedSceneValue(
                \.selectNextEditorTab,
                editor.tabs.count > 1 ? { Task { await editor.selectNextTab() } } : nil
            )
            .focusedSceneValue(
                \.moveEditorTabLeft,
                editor.canMoveActiveTab(by: -1) ? { editor.moveActiveTab(by: -1) } : nil
            )
            .focusedSceneValue(
                \.moveEditorTabRight,
                editor.canMoveActiveTab(by: 1) ? { editor.moveActiveTab(by: 1) } : nil
            )
    }
}

#if DEBUG
#Preview {
    AppView(environment: .preview)
        .frame(width: 980, height: 620)
}
#endif
