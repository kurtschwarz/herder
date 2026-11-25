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

    /// Whether the history lists every ended session. Per window, and not saved.
    @State private var showsAllHistory = false

    /// What this window lists, read straight off the model. This was a `@Query`
    /// against SwiftData; Observation does the same job, and the sidebar no
    /// longer knows what backs it.
    private var repositories: [Repository] { model.repositories }

    /// The part of it the workspace selector has left on screen. Only these
    /// are read: a hidden repository's worktrees are nobody's business.
    private var shown: [Repository] { model.shownRepositories }

    private var historySources: [RepositoriesModel.HistorySource] { model.historySources(of: shown) }

    @Environment(AgentSessions.self) private var history: AgentSessions?

    /// How many ended sessions the shown repositories have between them.
    private var historyCount: Int {
        guard let history else { return 0 }
        var seen: Set<PathKey> = []
        return historySources.reduce(0) { total, source in
            seen.insert(source.key).inserted ? total + history.ended(in: source.key).count : total
        }
    }

    public init(model: RepositoriesModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            RepositoriesHeader(model: model)

            if repositories.isEmpty {
                EmptyRepositories { model.beginAdding() }
            } else {
                NewOrderCard(model: model)
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            OpenSessionsSection(model: model, repositories: shown)
                            SessionHistorySection(
                                sources: historySources,
                                isExpanded: $showsAllHistory
                            )
                            if !showsAllHistory, historyCount > 0 {
                                AllHistoryRow(count: historyCount, isExpanded: $showsAllHistory)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.tight)
                        .padding(.bottom, Theme.Spacing.loose)
                    }
                    .scrollIndicators(.hidden)
                    // Expanded, the row is pinned under the list, and rows
                    // fade out as they near it rather than running under it.
                    .mask(alignment: .bottom) {
                        VStack(spacing: 0) {
                            Color.black
                            if showsAllHistory {
                                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                                    .frame(height: Theme.Spacing.loose)
                            }
                        }
                    }

                    if showsAllHistory, historyCount > 0 {
                        AllHistoryRow(count: historyCount, isExpanded: $showsAllHistory)
                            .padding(.horizontal, Theme.Spacing.tight)
                            .padding(.bottom, Theme.Spacing.tight)
                    }
                }
                // Here rather than on the history, which a lazy stack
                // may not build while there is nothing to show yet.
                .task(id: historySources.map(\.key)) {
                    guard let history else { return }
                    for source in historySources { await history.load(source.key) }
                }
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
                WorkspaceSelector(
                    model: model,
                    selection: .multiple(Binding(
                        get: { Set(model.shownRepositories.map(\.id)) },
                        set: { model.setShown($0) }
                    ))
                )
            }
        }
        // The selector is a plate of its own, so it sits off the pane's edge
        // by the same gap the pane sits off the window's.
        .padding(.leading, model.repositories.isEmpty ? Theme.Spacing.paneInset : Theme.Spacing.windowPadding)
        // The selector's trailing edge lines up with the launcher's plus below.
        .padding(.trailing, model.repositories.isEmpty ? Theme.Spacing.paneInset : Theme.Spacing.windowPadding)
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
    let settings = UserSettingsStore.inMemory()

    RepositoriesView(model: RepositoriesModel(
        repositories: list, git: git, picker: StubFolderPickerClient(), namer: StubSessionNamer(),
        naming: NamingSettings(settings: settings, vault: InMemoryNamingKeyVault()),
        agents: AgentCatalog(state: InMemoryStateStore(), settings: settings)
    ))
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
