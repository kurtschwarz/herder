import Core
import DesignSystem
import Storage
import SwiftUI

/// A workspace row and, while it is open, the worktrees beneath it.
struct WorkspaceSection: View {
    let workspace: Repository
    let model: WorkspacesModel

    /// Whichever workspace this window resolved, or `nil` for none. How a row
    /// knows it is the active one, without anything asking "which is active?".
    @Environment(Workspace.self) private var active: Workspace?

    /// How a row asks to become the active one. Inert outside a window, which
    /// is what lets the previews below render.
    @Environment(\.openWorkspace) private var openWorkspace

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
        .animation(.easeOut(duration: 0.15), value: model.isExpanded(workspace))
        .clipped()
    }
}
