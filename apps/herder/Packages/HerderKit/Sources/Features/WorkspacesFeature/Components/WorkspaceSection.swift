import Clients
import DesignSystem
import Storage
import SwiftUI

/// A workspace row and, while it is open, the worktrees beneath it.
struct WorkspaceSection: View {
    let workspace: Workspace
    let model: WorkspacesModel

    @State private var hoveredWorktree: GitWorktree.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkspaceRow(workspace: workspace, model: model)

            if model.isExpanded(workspace) {
                HStack(alignment: .top, spacing: 0) {
                    // Sits under the chevron, tying the rows to their workspace.
                    Rectangle()
                        .fill(Theme.Palette.hairline)
                        .frame(width: 1)
                        // The hover plate sits right against the line; with
                        // both showing, the plate's edge reads as a double rule.
                        .opacity(hoveredWorktree == nil ? 1 : 0)
                        .animation(.easeOut(duration: 0.1), value: hoveredWorktree == nil)
                        .padding(.leading, Theme.Spacing.normal + Theme.Size.chevron / 2)

                    VStack(alignment: .leading, spacing: 0) {
                        switch model.listings[workspace.id] {
                        case .loaded(let worktrees):
                            ForEach(worktrees) { WorktreeRow(worktree: $0, hovered: $hoveredWorktree) }
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
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.isExpanded(workspace))
        .clipped()
    }
}
