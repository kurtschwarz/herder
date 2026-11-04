import Clients
import DesignSystem
import PhosphorSwift
import SwiftUI

/// The new-session modal, drawn over the whole window like the add-workspace
/// one, and for the same reason: the scrim has to cover both panes.
public struct NewSessionOverlay: View {
    private let model: WorkspacesModel

    public init(model: WorkspacesModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            if let session = model.newSession {
                Theme.Palette.scrim
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { model.cancelNewSession() }
                    .transition(.opacity)

                NewSessionCard(
                    model: session,
                    cancel: { model.cancelNewSession() },
                    submit: { Task { await model.submitNewSession() } }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.newSession != nil)
    }
}

private struct NewSessionCard: View {
    let model: NewSessionModel
    let cancel: () -> Void
    let submit: () -> Void

    @FocusState private var isFilterFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            header

            Text("Worktree")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Palette.secondaryText)

            VStack(alignment: .leading, spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
                NewWorktreeCard(model: model)
                existingWorktrees
            }

            if let failure = model.failure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(Theme.Palette.warning)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            buttons
        }
        .padding(Theme.Spacing.section)
        .frame(width: Theme.Size.wideModalWidth)
        .modalSurface()
        .task { await model.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            HStack(spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
                WolfMark()
                Text("New session")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.Palette.text)
            }
            Text("in \(model.workspaceName)")
                .foregroundStyle(Theme.Palette.secondaryText)
        }
    }

    private var existingWorktrees: some View {
        let worktrees = model.filteredWorktrees

        return VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
                PhIcon(Ph.magnifyingGlass.regular, size: 16)
                    .foregroundStyle(Theme.Palette.secondaryText)
                TextField(
                    "Filter",
                    text: Bindable(model).filter,
                    prompt: Text("Filter \(model.worktrees.count) worktrees…")
                        .foregroundStyle(Theme.Palette.tertiaryText)
                )
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.Palette.text)
                .focused($isFilterFocused)

                Text("⌘F")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .padding(.horizontal, Theme.Spacing.normal - 2)
                    .padding(.vertical, 2)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                    }
            }
            .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
            .frame(minHeight: Theme.Size.control + 8)
            // Nothing visible: the badge above is the only sign of it.
            .background {
                Button("") { isFilterFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .opacity(0)
            }

            Rectangle().fill(Theme.Palette.hairline).frame(height: 1)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    Text("WORKTREES")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .padding(.horizontal, Theme.Spacing.normal)
                        .padding(.vertical, Theme.Spacing.normal)

                    if worktrees.isEmpty {
                        Text(model.isLoading ? "Reading worktrees…" : "No worktrees match.")
                            .font(.callout)
                            .foregroundStyle(Theme.Palette.tertiaryText)
                            .padding(.horizontal, Theme.Spacing.normal)
                            .padding(.bottom, Theme.Spacing.normal)
                    }

                    ForEach(worktrees) { worktree in
                        WorktreeChoiceRow(
                            worktree: worktree,
                            isSelected: model.choice == .existing(worktree.id)
                        ) { model.select(worktree) }
                    }
                }
                .padding(.horizontal, Theme.Spacing.normal)
                .padding(.bottom, Theme.Spacing.normal)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 220)
        }
        .fieldGroupSurface()
    }

    private var buttons: some View {
        HStack(spacing: Theme.Spacing.normal) {
            Spacer(minLength: 0)

            Button("Cancel", action: cancel)
                .buttonStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                .disabled(model.isCreating)

            Button(action: submit) {
                ZStack {
                    Text(primaryLabel).opacity(model.isCreating ? 0 : 1)
                    if model.isCreating {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .buttonStyle(.primary)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canCreate)
            .help(model.choice == .newWorktree ? "" : "Sessions can't be opened yet.")
        }
    }

    private var primaryLabel: String {
        model.choice == .newWorktree ? "Create worktree & open session" : "Open session"
    }
}

/// The "New worktree" choice: a branch name, and the branch to cut it from.
private struct NewWorktreeCard: View {
    let model: NewSessionModel

    private var isSelected: Bool { model.choice == .newWorktree }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.fieldGroup, style: .continuous)

        VStack(alignment: .leading, spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
            HStack(spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
                RadioDot(isSelected: isSelected)
                PhIcon(Ph.gitFork.regular, size: 18)
                    .foregroundStyle(Theme.Palette.violet)
                Text("New worktree")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Palette.text)
            }

            HStack(spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
                TextField(
                    "Branch",
                    text: Binding(get: { model.branchName }, set: { model.editBranchName($0) }),
                    prompt: Text("agent/add-minimap").foregroundStyle(Theme.Palette.tertiaryText)
                )
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Theme.Palette.text)
                .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
                .frame(minHeight: Theme.Size.control + 6)
                .fieldSurface()

                Text("from")
                    .foregroundStyle(Theme.Palette.secondaryText)

                baseMenu
            }
            .padding(.leading, 30)

            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(Theme.Palette.warning)
                    .padding(.leading, 30)
            } else if let location = model.location {
                Text(location.path(percentEncoded: false))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .padding(.leading, 30)
            }
        }
        .padding(Theme.Spacing.normal + Theme.Spacing.tight)
        .background {
            shape.fill(isSelected ? Theme.Palette.violet.opacity(0.12) : Theme.Palette.fieldGroup)
        }
        .overlay {
            shape.strokeBorder(isSelected ? Theme.Palette.violet.opacity(0.7) : Theme.Palette.hairline, lineWidth: 1.5)
        }
        .contentShape(shape)
        .onTapGesture { model.selectNewWorktree() }
    }

    private var baseMenu: some View {
        BaseBranchPicker(model: model)
    }

    private var message: String? {
        switch model.nameProblem {
        case .invalid(let reason): "A branch name \(reason)."
        case .alreadyExists: "A branch called \(model.branchName) already exists."
        case nil: nil
        }
    }
}

/// A button that opens a list of branches in a popover. Not a `Menu`: a menu
/// flattens its label into a native control that drops padding and ignores a
/// custom view's frame, which is what makes a field-styled menu impossible.
private struct BaseBranchPicker: View {
    let model: NewSessionModel

    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: Theme.Spacing.normal) {
                Text(model.baseBranch.isEmpty ? "—" : model.baseBranch)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(1)
                PhIcon(Ph.caretUpDown.regular, size: 12)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
            .frame(minHeight: Theme.Size.control + 6)
            .fieldSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(model.branches.isEmpty)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.branches, id: \.self) { branch in
                        BranchOption(branch: branch, isSelected: branch == model.baseBranch) {
                            model.baseBranch = branch
                            isOpen = false
                        }
                    }
                }
                .padding(Theme.Spacing.tight)
            }
            .frame(minWidth: 200, maxHeight: 240)
        }
    }
}

private struct BranchOption: View {
    let branch: String
    let isSelected: Bool
    let choose: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: choose) {
            HStack {
                Text(branch)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.loose)
                if isSelected {
                    PhIcon(Ph.check.bold, size: 12)
                }
            }
            .padding(.horizontal, Theme.Spacing.normal)
            .frame(minHeight: 26)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Theme.Palette.control : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct WorktreeChoiceRow: View {
    let worktree: GitWorktree
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
            RadioDot(isSelected: isSelected)
            PhIcon(Ph.gitBranch.regular, size: 16)
                .foregroundStyle(Theme.Palette.secondaryText)
            Text(NewSessionModel.label(of: worktree))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Theme.Palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if let date = worktree.lastActivity {
                Text(RelativeAge.short(from: date))
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
        }
        .padding(.horizontal, Theme.Spacing.normal)
        .frame(minHeight: 32)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(isSelected || isHovering ? Theme.Palette.control : .clear)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: select)
    }
}

private struct RadioDot: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? .clear : Theme.Palette.tertiaryText, lineWidth: 1.5)
            if isSelected {
                Circle().fill(Theme.Palette.violet)
                Circle().fill(Theme.Palette.onViolet).frame(width: 8, height: 8)
            }
        }
        .frame(width: 20, height: 20)
    }
}
