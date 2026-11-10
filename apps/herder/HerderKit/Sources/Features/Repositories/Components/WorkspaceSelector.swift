import AppKit
import Core
import DesignSystem
import SwiftUI

/// The sidebar's title, as a button: says which workspaces are showing, and
/// opens a list to tick more of them. A popover rather than a `Menu`, for the
/// reason `BaseBranchPicker` gives, and because a menu closes on every pick.
struct WorkspaceSelector: View {
    let model: RepositoriesModel

    @State private var isOpen = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.control + 3, style: .continuous)
    }

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: Theme.Spacing.normal) {
                PhIcon(Ph.folderSimpleDuotone, size: 16)
                    .foregroundStyle(Theme.Palette.violet)
                Text(model.selectionTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                PhIcon(Ph.caretUpDown, size: 12)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.control)
            .background(Theme.Palette.control, in: shape)
            .overlay {
                shape.strokeBorder(isOpen ? Theme.Palette.violet : Theme.Palette.hairline, lineWidth: 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help("Choose which workspaces to show")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            WorkspaceSelection(model: model) { isOpen = false }
        }
    }
}

/// The popover: one box per repository this window lists.
private struct WorkspaceSelection: View {
    let model: RepositoriesModel
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Show sessions from")
                .textCase(.uppercase)
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(Theme.Palette.tertiaryText)
                .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
                .padding(.top, Theme.Spacing.normal)
                .padding(.bottom, Theme.Spacing.tight)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.repositories) { repository in
                        WorkspaceOption(
                            repository: repository,
                            model: model,
                            isOn: model.isShown(repository),
                            isEnabled: !model.isShown(repository) || model.canHide(repository)
                        ) { model.setShown(repository, !model.isShown(repository)) }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 280)

            Divider()
                .padding(.vertical, Theme.Spacing.normal)

            HStack(spacing: Theme.Spacing.normal) {
                Button { model.showAll() } label: {
                    Text("Select all").frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondary)
                .disabled(model.shownRepositories.count == model.repositories.count)

                Button(action: done) {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.normal)
        .frame(width: 260)
    }
}

/// One repository in the selector: ticked to show its sessions, and, with a
/// right click, revealed, renamed or taken out of this window. The sidebar has
/// no row of its own for a repository, so this is where those live.
private struct WorkspaceOption: View {
    let repository: Repository
    let model: RepositoriesModel
    let isOn: Bool
    let isEnabled: Bool
    let toggle: () -> Void

    @State private var isHovering = false

    private var isRenaming: Bool { model.renaming == repository.id }

    /// Not a `Button`: a text field in a button's label does not take the
    /// keyboard, and a disabled button takes its context menu down with it,
    /// which would leave the last repository on show with no way to rename or
    /// remove it.
    var body: some View {
        HStack(spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
            CheckBox(isOn: isOn)
                .opacity(isEnabled ? 1 : 0.5)
            if isRenaming {
                RenameField(name: repository.name) { name in
                    Task { await model.commitRename(repository, to: name) }
                }
            } else {
                Text(repository.name)
                    .font(.system(size: 13))
                    .foregroundStyle(repository.isAvailable ? Theme.Palette.text : Theme.Palette.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            if !repository.isAvailable {
                PhIcon(Ph.warningFill, size: 12)
                    .foregroundStyle(Theme.Palette.warning)
            }
        }
        .padding(.horizontal, Theme.Spacing.normal)
        .frame(minHeight: 32)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(isHovering && isEnabled && !isRenaming ? Theme.Palette.control : .clear)
        }
        .contentShape(Rectangle())
        .onTapGesture { if isEnabled, !isRenaming { toggle() } }
        .accessibilityAddTraits(.isButton)
        .onHover { isHovering = $0 }
        .help(help)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([repository.url])
            }
            .disabled(!repository.isAvailable)

            Button("Rename") { model.renaming = repository.id }

            Divider()

            // This window's list only: other windows keep it, and so does the
            // app, which is why this is not a deletion.
            Button("Remove from This Window", role: .destructive) {
                model.remove(repository)
            }
        }
    }

    private var help: String {
        if !repository.isAvailable { return "\(repository.path) can\u{2019}t be reached" }
        return isEnabled ? repository.path : "At least one workspace stays on the sidebar"
    }
}

private struct CheckBox: View {
    let isOn: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        ZStack {
            if isOn {
                shape.fill(Theme.Palette.violet)
                PhIcon(Ph.checkBold, size: 11)
                    .foregroundStyle(Theme.Palette.onViolet)
            } else {
                shape.strokeBorder(Theme.Palette.tertiaryText, lineWidth: 1.5)
            }
        }
        .frame(width: 18, height: 18)
    }
}
