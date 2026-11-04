import AppKit
import DesignSystem
import Storage
import SwiftData
import SwiftUI

/// The sidebar's workspace list: a pinned header over a scrolling tree of
/// workspaces and their worktrees.
public struct WorkspacesView: View {
    @Query(sort: [SortDescriptor(\Workspace.order), SortDescriptor(\Workspace.addedAt)])
    private var workspaces: [Workspace]

    private let model: WorkspacesModel

    public init(model: WorkspacesModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            WorkspacesHeader { model.isAddingWorkspace = true }

            if workspaces.isEmpty {
                EmptyWorkspaces { model.isAddingWorkspace = true }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                        ForEach(workspaces) { workspace in
                            WorkspaceSection(workspace: workspace, model: model)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.normal)
                    .padding(.bottom, Theme.Spacing.loose)
                }
                .scrollIndicators(.hidden)
            }
        }
        // Worktrees are made and removed in a terminal, so coming back to the
        // app is the moment they may have changed.
        .task(id: workspaces.map(\.id)) { await model.refresh(workspaces) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await model.refresh(workspaces) }
        }
    }
}

private struct WorkspacesHeader: View {
    let add: () -> Void

    var body: some View {
        HStack {
            Text("Workspaces")
                .font(.headline)
                .foregroundStyle(Theme.Palette.text)
            Spacer(minLength: 0)
            Button(action: add) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Add workspace")
        }
        .padding(.horizontal, Theme.Spacing.paneInset)
        .padding(.bottom, Theme.Spacing.normal)
    }
}

private struct EmptyWorkspaces: View {
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
