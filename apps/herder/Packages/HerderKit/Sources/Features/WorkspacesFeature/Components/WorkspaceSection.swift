import DesignSystem
import Storage
import SwiftUI

/// A workspace row and, while it is open, the worktrees beneath it.
struct WorkspaceSection: View {
    let workspace: Workspace
    let model: WorkspacesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkspaceRow(workspace: workspace, model: model)

            if model.isExpanded(workspace) {
                VStack(alignment: .leading, spacing: 0) {
                    switch model.listings[workspace.id] {
                    case .loaded(let worktrees):
                        ForEach(worktrees) { worktree in
                            WorktreeRow(
                                worktree: worktree,
                                isSelected: model.selectedWorktree == worktree.path
                            ) { model.select(worktree, in: workspace) }
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
        .animation(.easeOut(duration: 0.15), value: model.isExpanded(workspace))
        .clipped()
    }
}
