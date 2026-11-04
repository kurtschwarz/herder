import DesignSystem
import SwiftUI

/// The add-workspace modal, drawn over the whole window.
///
/// Rendered by `AppView` rather than by the sidebar: an overlay inside the
/// sidebar cannot reach past its edge, and the scrim has to cover both panes.
public struct AddWorkspaceOverlay: View {
    private let model: WorkspacesModel

    public init(model: WorkspacesModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            if let adding = model.adding {
                Theme.Palette.scrim
                    .contentShape(Rectangle())
                    .onTapGesture { model.cancelAdding() }
                    .transition(.opacity)

                AddWorkspaceCard(
                    model: adding,
                    cancel: { model.cancelAdding() },
                    submit: { Task { await model.submitAdding() } }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.adding != nil)
    }
}

private struct AddWorkspaceCard: View {
    let model: AddWorkspaceModel
    let cancel: () -> Void
    let submit: () -> Void

    private let labelWidth: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text("Add workspace")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.Palette.text)
                Text("Open a git repository to add it to the sidebar.")
                    .foregroundStyle(Theme.Palette.secondaryText)
            }

            fields

            HStack(spacing: Theme.Spacing.normal) {
                Spacer(minLength: 0)
                Button("Cancel", action: cancel)
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isSubmitting)

                Button(action: submit) {
                    ZStack {
                        Text("Add workspace").opacity(model.isSubmitting ? 0 : 1)
                        if model.isSubmitting {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canAdd)
            }
        }
        .padding(Theme.Spacing.section)
        .frame(width: Theme.Size.modalWidth)
        .modalSurface()
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            HStack(spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
                label("Folder")
                path
                Button("Browse…") { Task { await model.browse() } }
                    .buttonStyle(.secondary)
                    .disabled(model.isSubmitting)
            }

            if let refusal = model.refusal {
                RefusalMessage(refusal: refusal) { Task { await model.chooseMainRepository() } }
                    .padding(.leading, labelWidth + Theme.Spacing.normal + Theme.Spacing.tight)
            }

            HStack(spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
                label("Name")
                TextField(
                    "Name",
                    text: Binding(get: { model.name }, set: { model.editName($0) }),
                    prompt: Text("Workspace name").foregroundStyle(Theme.Palette.tertiaryText)
                )
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.Palette.text)
                .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
                .frame(minHeight: Theme.Size.control)
                .fieldSurface()
                .disabled(model.folder == nil || model.isSubmitting)
            }

            Text("Its worktrees come along too.")
                .font(.callout)
                .foregroundStyle(Theme.Palette.secondaryText)
                .padding(.leading, labelWidth + Theme.Spacing.normal + Theme.Spacing.tight)
        }
        .padding(Theme.Spacing.loose)
        .fieldGroupSurface()
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .fontWeight(.medium)
            .foregroundStyle(Theme.Palette.text)
            .frame(width: labelWidth, alignment: .leading)
    }

    /// Read-only: under the sandbox a typed path grants nothing, so the only
    /// way to set it is Browse…
    private var path: some View {
        Group {
            if let folder = model.folder {
                Text(folder.path(percentEncoded: false))
                    .foregroundStyle(Theme.Palette.text)
            } else {
                Text("Choose a folder…")
                    .foregroundStyle(Theme.Palette.tertiaryText)
            }
        }
        .font(.system(.body, design: .monospaced))
        .lineLimit(1)
        .truncationMode(.head)
        .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
        .frame(maxWidth: .infinity, minHeight: Theme.Size.control, alignment: .leading)
        .fieldSurface()
    }
}

private struct RefusalMessage: View {
    let refusal: AddWorkspaceModel.Refusal
    let chooseMainRepository: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.normal) {
            Label {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.callout)
            .foregroundStyle(Theme.Palette.warning)

            if case .linkedWorktree(let main) = refusal {
                Button("Choose \(main.lastPathComponent)…", action: chooseMainRepository)
                    .buttonStyle(.secondary)
            }
        }
    }

    private var message: String {
        switch refusal {
        case .notARepository:
            "That folder isn't a git repository. Choose the folder that contains .git."
        case .linkedWorktree(let main):
            "That's a worktree of \(main.lastPathComponent). Add the repository instead and its worktrees come along."
        case .alreadyOpen:
            "That folder is already in the sidebar."
        case .failed(let reason):
            reason
        }
    }
}
