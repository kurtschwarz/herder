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
        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
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
        .pointerStyle(.link)
        .help(isMultiple ? "Choose which workspaces to show" : "Choose a workspace")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            WorkspaceSelection(
                model: model,
                picked: picked,
                isMultiple: isMultiple,
                toggle: toggle,
                addWorkspace: {
                    isOpen = false
                    model.beginAdding()
                }
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

/// The size of the list: the row and the cap on the list share one height, so
/// exactly ten rows show with nothing peeking.
private enum WorkspaceList {
    static let rowHeight: CGFloat = 32
    static let gap: CGFloat = 2
    static let visibleRows: CGFloat = 10
    static let maxHeight = visibleRows * rowHeight + (visibleRows - 1) * gap
}

/// The popover: a search field over one row per repository this window lists.
private struct WorkspaceSelection: View {
    let model: RepositoriesModel
    let picked: Set<UUID>
    let isMultiple: Bool
    let toggle: (Repository) -> Void
    let addWorkspace: () -> Void

    /// Reset each time the popover opens, because the popover's content is
    /// made afresh then.
    @State private var query = ""
    @FocusState private var isSearching: Bool

    private var matches: [Repository] { model.matching(query) }

    private var searchShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
    }

    private var search: some View {
        HStack(spacing: Theme.Spacing.normal) {
            PhIcon(Ph.magnifyingGlass, size: 14)
                .foregroundStyle(Theme.Palette.secondaryText)
            TextField("Search workspaces", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearching)
                .onSubmit {
                    if let repository = model.soleMatch(for: query) { toggle(repository) }
                }
        }
        .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
        .frame(minHeight: Theme.Size.control)
        .background(Theme.Palette.control, in: searchShape)
        .overlay {
            searchShape.strokeBorder(isSearching ? Theme.Palette.violet : Theme.Palette.hairline, lineWidth: 1)
        }
        .padding(.bottom, Theme.Spacing.normal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            search

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
                VStack(alignment: .leading, spacing: WorkspaceList.gap) {
                    if matches.isEmpty {
                        Text("No matching workspaces")
                            .font(.callout)
                            .foregroundStyle(Theme.Palette.tertiaryText)
                            .padding(Theme.Spacing.normal)
                    }
                    ForEach(matches) { repository in
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
            .frame(maxHeight: WorkspaceList.maxHeight)

            if isMultiple {
                Divider()
                    .padding(.vertical, Theme.Spacing.normal)

                AddWorkspaceOption(action: addWorkspace)
            }
        }
        .padding(Theme.Spacing.normal)
        .frame(width: 260)
        .onAppear { isSearching = true }
    }

    /// One workspace must be somewhere you can work in. Several must keep one
    /// ticked, so the sidebar is never empty while it lists any.
    private func isEnabled(_ repository: Repository) -> Bool {
        guard isMultiple else { return repository.isAvailable }
        return !picked.contains(repository.id) || picked.count > 1
    }
}

/// The row under the list that opens the Add workspace modal. The ⌘O is a
/// label: the File menu owns the shortcut.
private struct AddWorkspaceOption: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
            PhIcon(Ph.folderSimplePlus, size: 16)
                .foregroundStyle(Theme.Palette.secondaryText)
            Text("Add workspace…")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.text)
            Spacer(minLength: 0)
            Text("⌘O")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.secondaryText)
        }
        .padding(.horizontal, Theme.Spacing.normal)
        .frame(minHeight: WorkspaceList.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(isHovering ? Theme.Palette.control : .clear)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .pointerStyle(.link)
        .accessibilityAddTraits(.isButton)
        .onHover { isHovering = $0 }
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
        .frame(minHeight: WorkspaceList.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(isHovering && isEnabled && !isRenaming ? Theme.Palette.control : .clear)
        }
        .contentShape(Rectangle())
        .onTapGesture { if isEnabled, !isRenaming { toggle() } }
        .pointerStyle(isEnabled && !isRenaming ? .link : nil)
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
