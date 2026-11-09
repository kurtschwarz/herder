import AppKit
import Core
import DesignSystem
import SwiftUI
import TestSupport

/// The sidebar's repository list: a pinned header over a scrolling tree of
/// repositories and their worktrees.
public struct RepositoriesView: View {
    private let model: RepositoriesModel

    /// What this window lists, read straight off the model. This was a `@Query`
    /// against SwiftData; Observation does the same job, and the sidebar no
    /// longer knows what backs it.
    private var repositories: [Repository] { model.repositories }

    public init(model: RepositoriesModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            RepositoriesHeader { model.beginAdding() }

            if repositories.isEmpty {
                EmptyRepositories { model.beginAdding() }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(repositories) { repository in
                            RepositorySection(repository: repository, model: model)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.tight)
                    .padding(.bottom, Theme.Spacing.loose)
                }
                .scrollIndicators(.hidden)
            }
        }
        // Worktrees are made and removed in a terminal, so coming back to the
        // app is the moment they may have changed.
        .task(id: repositories.map(\.id)) { await model.refresh(repositories) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await model.refresh(repositories) }
        }
    }
}

private struct RepositoriesHeader: View {
    let add: () -> Void

    var body: some View {
        HStack {
            Text("Workspaces")
                .font(.headline)
                .foregroundStyle(Theme.Palette.text)
            Spacer(minLength: 0)
            Button(action: add) {
                PhIcon(Ph.folderSimplePlus, size: 18)
            }
            .buttonStyle(.icon)
            .help("Add workspace")
            // Centred under the wolf mark above it, which sits flush with the
            // pane inset: the plate is wider than the mark, so it overhangs.
            .padding(.trailing, -(Theme.Size.iconButton - Theme.Size.wolfMark.width) / 2)
        }
        .padding(.horizontal, Theme.Spacing.paneInset)
        // Matched by the file tree's header, so the two titles stay level.
        .padding(.top, Theme.Spacing.normal + Theme.Spacing.tight)
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
