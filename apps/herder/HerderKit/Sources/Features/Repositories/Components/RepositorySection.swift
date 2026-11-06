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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RepositoryRow(repository: repository, model: model)

            if model.isExpanded(repository) {
                VStack(alignment: .leading, spacing: 0) {
                    switch model.listings[repository.id] {
                    case .loaded(let worktrees):
                        ForEach(worktrees) { worktree in
                            WorktreeRow(
                                worktree: worktree,
                                isSelected: active?.root == PathKey(worktree.path)
                            ) { openWorkspace(WorkspaceID(worktree.path)) }
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
}
