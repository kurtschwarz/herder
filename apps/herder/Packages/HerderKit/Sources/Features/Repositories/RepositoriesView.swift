import AppKit
import Core
import DesignSystem
import PhosphorSwift
import SwiftUI
import TestSupport

/// The sidebar's repository list: a pinned header over a scrolling tree of
/// repositories and their worktrees.
public struct RepositoriesView: View {
    private let model: RepositoriesModel

    /// The list, read straight off the store. This was a `@Query` against
    /// SwiftData; Observation does the same job, and the sidebar no longer
    /// knows what backs it.
    private let store: RepositoryStore

    private var repositories: [Repository] { store.repositories }

    public init(model: RepositoriesModel, store: RepositoryStore) {
        self.model = model
        self.store = store
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
                PhIcon(Ph.folderSimplePlus.regular, size: 18)
            }
            .buttonStyle(.icon)
            .help("Add workspace")
            // Centred under the wolf mark above it, which sits flush with the
            // pane inset: the plate is wider than the mark, so it overhangs.
            .padding(.trailing, -(Theme.Size.iconButton - Theme.Size.wolfMark.width) / 2)
        }
        .padding(.horizontal, Theme.Spacing.paneInset)
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

    RepositoriesView(
        model: RepositoriesModel(store: store, git: git, picker: StubFolderPickerClient()),
        store: store
    )
    .frame(width: Theme.Size.sidebarWidth, height: 420)
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
            _ = try? await store.add(url: url, name: name)
        }
    }
}
#endif
