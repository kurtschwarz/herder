import AppKit
import Core
import DesignSystem
import SwiftUI
import TestSupport

/// The sidebar: the workspace selector pinned over the sessions open in the
/// repositories it has on show, then the sessions that have ended in them.
/// Repositories and worktrees are not rows: a session says where it runs.
public struct RepositoriesView: View {
    private let model: RepositoriesModel

    /// What this window lists, read straight off the model. This was a `@Query`
    /// against SwiftData; Observation does the same job, and the sidebar no
    /// longer knows what backs it.
    private var repositories: [Repository] { model.repositories }

    /// The part of it the workspace selector has left on screen. Only these
    /// are read: a hidden repository's worktrees are nobody's business.
    private var shown: [Repository] { model.shownRepositories }

    public init(model: RepositoriesModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            RepositoriesHeader(model: model)

            if repositories.isEmpty {
                EmptyRepositories { model.beginAdding() }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        OpenSessionsSection(model: model, repositories: shown)
                        SessionHistorySection(sources: model.historySources(of: shown))
                    }
                    .padding(.horizontal, Theme.Spacing.tight)
                    .padding(.bottom, Theme.Spacing.loose)
                }
                .scrollIndicators(.hidden)
            }
        }
        // Worktrees are made and removed in a terminal, so coming back to the
        // app is the moment they may have changed.
        .task(id: shown.map(\.id)) { await model.refresh(shown) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await model.refresh(shown) }
        }
    }
}

private struct RepositoriesHeader: View {
    let model: RepositoriesModel

    var body: some View {
        HStack(spacing: Theme.Spacing.normal) {
            if model.repositories.isEmpty {
                Text("Workspaces")
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.text)
                Spacer(minLength: 0)
            } else {
                WorkspaceSelector(model: model)
            }
            Button { model.beginAdding() } label: {
                PhIcon(Ph.folderSimplePlus, size: 18)
            }
            .buttonStyle(.icon)
            .help("Add workspace")
            // Centred under the wolf mark above it, which sits flush with the
            // pane inset: the plate is wider than the mark, so it overhangs.
            .padding(.trailing, -(Theme.Size.iconButton - Theme.Size.wolfMark.width) / 2)
        }
        // The selector is a plate of its own, so it sits off the pane's edge
        // by the same gap the pane sits off the window's.
        .padding(.leading, model.repositories.isEmpty ? Theme.Spacing.paneInset : Theme.Spacing.windowPadding)
        .padding(.trailing, Theme.Spacing.paneInset)
        // The plain title is matched by the file tree's header, so the two
        // stay level. The selector is taller, and tucks up under the traffic
        // lights instead.
        .padding(.top, model.repositories.isEmpty ? Theme.Spacing.normal + Theme.Spacing.tight : 0)
        .padding(.bottom, Theme.Spacing.normal)
    }
}

private struct EmptyRepositories: View {
    let add: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.normal) {
            Text("No workspaces yet. Add a git repository to see its worktrees here.")
                .font(.callout)
                .foregroundStyle(Theme.Palette.secondaryText)
            Button("Add workspace", action: add)
                .buttonStyle(.secondary)
        }
        .padding(.horizontal, Theme.Spacing.paneInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview {
    let git = StubGitClient()
    let store = RepositoryStore(bookmarks: InMemoryBookmarkClient(), git: git, state: InMemoryStateStore())
    let list = WindowRepositories(store: store)

    RepositoriesView(model: RepositoriesModel(repositories: list, git: git, picker: StubFolderPickerClient()))
    .frame(width: Theme.Size.defaultSidebarWidth, height: 420)
    .glassPaneBackground()
    .padding(Theme.Spacing.windowPadding)
    .background(Theme.Palette.window)
    // Adding mints a bookmark, which is `async` even against a fake, so the
    // list fills in a frame after the pane appears rather than in the `let`
    // above.
    .task {
        for name in ["agent-editor", "herder"] {
            let url = URL(filePath: "/preview/\(name)")
            git.seed(url, .mainWorkingTree)
            git.seed(worktrees: [
                GitWorktree(path: url, checkout: .branch("main"), isMainWorkingTree: true),
                GitWorktree(
                    path: url.appending(path: "agent/add-minimap"),
                    checkout: .branch("agent/add-minimap"),
                    isMainWorkingTree: false
                ),
            ], at: url)
            _ = try? await list.add(url: url, name: name)
        }
    }
}
#endif
