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
                HStack(alignment: .top, spacing: 0) {
                    // Sits under the chevron, tying the rows to their workspace.
                    Rectangle()
                        .fill(Theme.Palette.hairline)
                        .frame(width: 1)
                        .padding(.leading, Theme.Spacing.normal + 12)

                    VStack(alignment: .leading, spacing: 0) {
                        switch model.listings[workspace.id] {
                        case .loaded(let worktrees):
                            ForEach(worktrees) { WorktreeRow(worktree: $0) }
                        case .unreadable:
                            Text("Couldn't read worktrees")
                                .font(.callout)
                                .foregroundStyle(Theme.Palette.tertiaryText)
                                .padding(.vertical, Theme.Spacing.tight)
                                .padding(.leading, Theme.Spacing.loose)
                        case nil:
                            EmptyView()
                        }
                    }
                }
            }
        }
    }
}
