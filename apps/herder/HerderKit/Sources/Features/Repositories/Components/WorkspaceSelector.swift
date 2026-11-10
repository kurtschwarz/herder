import AppKit
import Core
import DesignSystem
import SwiftUI

/// A button that says which workspaces are picked, and opens a list to pick
/// them. A popover rather than a `Menu`, for the reason `BaseBranchPicker`
/// gives, and because a multiple choice must stay open across picks.
///
/// ``Selection`` sets what kind of choice it is. One workspace closes the list
/// on pick and leaves out the ones that cannot be reached. Several keeps at
/// least one ticked, and is where a repository is revealed, renamed or taken
/// out of the window: the sidebar has no row of its own for one.
struct WorkspaceSelector: View {
    enum Selection {
        case single(Binding<UUID?>)
        case multiple(Binding<Set<UUID>>)
    }

    let model: RepositoriesModel
    let selection: Selection

    @State private var isOpen = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.control + 3, style: .continuous)
    }

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: Theme.Spacing.normal) {
                PhIcon(Ph.folderSimpleDuotone, size: 16)
                    .foregroundStyle(Theme.Palette.violet)
                Text(model.selectionTitle(for: picked))
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
        .help(isMultiple ? "Choose which workspaces to show" : "Choose a workspace")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            WorkspaceSelection(
                model: model,
                picked: picked,
                isMultiple: isMultiple,
                toggle: toggle,
                selectAll: { setPicked(Set(model.repositories.map(\.id))) },
                done: { isOpen = false }
            )
        }
    }

    private var isMultiple: Bool {
        if case .multiple = selection { true } else { false }
    }

    private var picked: Set<UUID> {
        switch selection {
        case .single(let binding): binding.wrappedValue.map { [$0] } ?? []
        case .multiple(let binding): binding.wrappedValue
        }
    }

    private func setPicked(_ ids: Set<UUID>) {
        if case .multiple(let binding) = selection { binding.wrappedValue = ids }
    }

    private func toggle(_ repository: Repository) {
        switch selection {
        case .single(let binding):
            binding.wrappedValue = repository.id
            isOpen = false
        case .multiple(let binding):
            if binding.wrappedValue.contains(repository.id) {
                binding.wrappedValue.remove(repository.id)
            } else {
                binding.wrappedValue.insert(repository.id)
            }
        }
    }
}

/// The popover: one row per repository this window lists.
private struct WorkspaceSelection: View {
    let model: RepositoriesModel
    let picked: Set<UUID>
    let isMultiple: Bool
    let toggle: (Repository) -> Void
    let selectAll: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isMultiple {
                Text("Show sessions from")
                    .textCase(.uppercase)
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
                    .padding(.top, Theme.Spacing.normal)
                    .padding(.bottom, Theme.Spacing.tight)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.repositories) { repository in
                        WorkspaceOption(
                            repository: repository,
                            model: model,
                            isOn: picked.contains(repository.id),
                            isMultiple: isMultiple,
                            isEnabled: isEnabled(repository)
                        ) { toggle(repository) }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 280)

            if isMultiple {
                Divider()
                    .padding(.vertical, Theme.Spacing.normal)

                HStack(spacing: Theme.Spacing.normal) {
                    Button(action: selectAll) {
                        Text("Select all").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.secondary)
                    .disabled(picked.count == model.repositories.count)

                    Button(action: done) {
                        Text("Done").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(Theme.Spacing.normal)
        .frame(width: 260)
    }

    /// One workspace must be somewhere you can work in. Several must keep one
    /// ticked, so the sidebar is never empty while it lists any.
    private func isEnabled(_ repository: Repository) -> Bool {
        guard isMultiple else { return repository.isAvailable }
        return !picked.contains(repository.id) || picked.count > 1
    }
}

/// One repository in the selector. Ticked, or checked when only one is
/// picked; with several, a right click reveals, renames or removes it.
private struct WorkspaceOption: View {
    let repository: Repository
    let model: RepositoriesModel
    let isOn: Bool
    let isMultiple: Bool
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
            if isMultiple {
                CheckBox(isOn: isOn)
                    .opacity(isEnabled ? 1 : 0.5)
            }
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
            if !isMultiple, isOn {
                PhIcon(Ph.checkBold, size: 12)
                    .foregroundStyle(Theme.Palette.text)
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
            if isMultiple {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([repository.url])
                }
                .disabled(!repository.isAvailable)

                Button("Rename") { model.renaming = repository.id }

                Divider()

                // This window's list only: other windows keep it, and so does
                // the app, which is why this is not a deletion.
                Button("Remove from This Window", role: .destructive) {
                    model.remove(repository)
                }
            }
        }
    }

    private var help: String {
        if !repository.isAvailable { return "\(repository.path) can\u{2019}t be reached" }
        if isEnabled || !isMultiple { return repository.path }
        return "At least one workspace stays on the sidebar"
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
