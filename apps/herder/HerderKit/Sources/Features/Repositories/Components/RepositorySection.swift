import Core
import DesignSystem
import SwiftUI

/// A repository row and, while it is open, the worktrees beneath it.
struct RepositorySection: View {
    let repository: Repository
    let model: RepositoriesModel

    /// Whichever workspace this window resolved, or `nil` for none. How a row
    /// knows it is the active one, without anything asking "which is active?".
    @Environment(Workspace.self) private var active: Workspace?

    /// How a row asks to become the active one. Inert outside a window, which
    /// is what lets the previews below render.
    @Environment(\.openWorkspace) private var openWorkspace

    @Environment(OpenAgentSessions.self) private var openSessions: OpenAgentSessions?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RepositoryRow(repository: repository, model: model, sessionCount: sessionCount)

            if model.isExpanded(repository) {
                VStack(alignment: .leading, spacing: 0) {
                    switch model.listings[repository.id] {
                    case .loaded(let worktrees):
                        ForEach(worktrees) { worktree in
                            WorktreeRow(
                                worktree: worktree,
                                isSelected: active?.root == PathKey(worktree.path)
                            ) { openWorkspace(WorkspaceID(worktree.path)) }

                            WorktreeAgentSessions(workspace: WorkspaceID(worktree.path))
                        }
                    case .unreadable:
                        Text("Couldn't read worktrees")
                            .font(.callout)
                            .foregroundStyle(Theme.Palette.tertiaryText)
                            .padding(.vertical, Theme.Spacing.tight)
                            .padding(.leading, Theme.Spacing.normal + Theme.Size.chevron / 2 + 1 + Theme.Spacing.loose)
                    case nil:
                        EmptyView()
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.isExpanded(repository))
        .clipped()
    }

    /// How many agent sessions this window has open in the repository's
    /// worktrees, for the badge on its row.
    private var sessionCount: Int {
        guard let openSessions, case .loaded(let worktrees)? = model.listings[repository.id] else { return 0 }
        let ids = Set(worktrees.map { WorkspaceID($0.path) })
        return openSessions.sessions.filter { ids.contains($0.workspace) }.count
    }
}
