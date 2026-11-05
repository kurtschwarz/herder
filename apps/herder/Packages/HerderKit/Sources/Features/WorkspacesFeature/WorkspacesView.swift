import AppKit
import Core
import DesignSystem
import PhosphorSwift
import SwiftUI

/// The sidebar's workspace list: a pinned header over a scrolling tree of
/// workspaces and their worktrees.
public struct WorkspacesView: View {
    private let model: WorkspacesModel

    /// The list, read straight off the store. This was a `@Query` against
    /// SwiftData; Observation does the same job, and the sidebar no longer
    /// knows what backs it.
    private let store: RepositoryStore

    private var workspaces: [Repository] { store.repositories }

    public init(model: WorkspacesModel, store: RepositoryStore) {
        self.model = model
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            WorkspacesHeader { model.beginAdding() }

            if workspaces.isEmpty {
                EmptyWorkspaces { model.beginAdding() }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(workspaces) { workspace in
                            WorkspaceSection(workspace: workspace, model: model)
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
