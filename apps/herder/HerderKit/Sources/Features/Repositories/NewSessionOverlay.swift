import Core
import DesignSystem
import SwiftUI

/// The new-session modal, drawn over the whole window like the add-repository
/// one, and for the same reason: the scrim has to cover both panes.
public struct NewSessionOverlay: View {
    private let model: RepositoriesModel

    @Environment(\.startAgentSession) private var startAgentSession
    @Environment(AgentCatalog.self) private var catalog: AgentCatalog?
    @Environment(WindowAgentSessions.self) private var open: WindowAgentSessions?
    @Environment(Workspace.self) private var active: Workspace?

    /// The agent the session starts with. Chosen afresh each time the modal
    /// opens, from the one used last, and kept when the repository changes.
    @State private var agentID: Agent.ID?

    public init(model: RepositoriesModel) {
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
                    workspaces: model,
                    agents: catalog?.agents.filter(\.isRunnable) ?? [],
                    agentID: $agentID,
                    activeWorktree: active?.id,
                    activity: { worktree in
                        WorktreeActivity(open?.sessions(in: WorkspaceID(worktree.path)) ?? [])
                    },
                    cancel: { model.cancelNewSession() },
                    submit: {
                        let agent = agentID.flatMap { catalog?.agent($0) }
                        Task {
                            if let worktree = await model.submitNewSession() {
                                startAgentSession(worktree, agent: agent)
                            }
                        }
                    }
                )
                .onAppear { agentID = catalog?.lastUsed.id }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.newSession != nil)
    }
}

private struct NewSessionCard: View {
    let model: NewSessionModel
    /// The window's repositories, for picking which one the session is in.
    let workspaces: RepositoriesModel
    let agents: [Agent]
    @Binding var agentID: Agent.ID?
    let activeWorktree: WorkspaceID?
    let activity: (GitWorktree) -> WorktreeActivity
    let cancel: () -> Void
    let submit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            header

            section("Workspace") { workspaceMenu }

            section("Where", detail: "\(model.worktrees.count) worktrees") {
                VStack(alignment: .leading, spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
                    worktreeList
                    if model.choice == .newWorktree {
                        NewWorktreePanel(model: model)
                    }
                }
            }

            if !agents.isEmpty {
                section("Agent") { agentChips }
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
        .task(id: ObjectIdentifier(model)) { await model.load() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text("New session")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.Palette.text)
                Text("In \(model.repositoryName). You type your first prompt in the agent.")
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            Spacer(minLength: Theme.Spacing.loose)
            Button(action: cancel) {
                PhIcon(Ph.xBold, size: 12)
            }
            .buttonStyle(.icon(size: 24))
            .disabled(model.isCreating)
            .help("Close")
        }
    }

    private func section<Content: View>(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
            HStack(spacing: Theme.Spacing.normal) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Palette.secondaryText)
                if let detail {
                    Text(detail)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                }
            }
            content()
        }
    }

    // MARK: - Workspace

    private var workspaceMenu: some View {
        WorkspaceSelector(
            model: workspaces,
            selection: .single(Binding(
                get: { workspaces.newSessionRepository?.id },
                set: { id in
                    if let repository = workspaces.repositories.first(where: { $0.id == id }) {
                        workspaces.switchNewSession(to: repository)
                    }
                }
            ))
        )
    }

    // MARK: - Where

    private var worktreeList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if model.worktrees.isEmpty {
                        Text(model.isLoading ? "Reading worktrees\u{2026}" : "No worktrees.")
                            .font(.callout)
                            .foregroundStyle(Theme.Palette.tertiaryText)
                            .padding(Theme.Spacing.normal)
                    }

                    ForEach(model.listedWorktrees) { worktree in
                        WorktreeChoiceRow(
                            worktree: worktree,
                            isDefault: worktree.id == model.defaultWorktree?.id,
                            isActive: WorkspaceID(worktree.path) == activeWorktree,
                            activity: activity(worktree),
                            isSelected: model.choice == .existing(worktree.id)
                        ) { model.select(worktree) }
                    }
                }
                .padding(Theme.Spacing.normal)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 5 * WorktreeChoiceRow.height)

            Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
                .padding(.horizontal, Theme.Spacing.loose)

            NewWorktreeRow(isSelected: model.choice == .newWorktree) { model.selectNewWorktree() }
                .padding(Theme.Spacing.normal)
        }
        .fieldGroupSurface()
    }

    // MARK: - Agent

    private var agentChips: some View {
        FlowLayout {
            ForEach(agents) { agent in
                ChoiceChip(title: agent.displayName, isSelected: agent.id == agentID) {
                    AgentBadge(id: agent.id, name: agent.displayName, size: 20)
                } action: { agentID = agent.id }
            }
        }
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
            .disabled(!model.canSubmit)
        }
    }

    private var primaryLabel: String {
        let isNew = model.choice == .newWorktree
        guard let name = agents.first(where: { $0.id == agentID })?.displayName else {
            return isNew ? "Create worktree & open session" : "Open session"
        }
        return isNew ? "Create worktree & start \(name)" : "Start \(name)"
    }
}

/// A pill to pick one of several things: a workspace or an agent.
private struct ChoiceChip<Leading: View>: View {
    let title: String
    var isSelected = false
    @ViewBuilder let leading: Leading
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous)

        Button(action: action) {
            HStack(spacing: Theme.Spacing.normal) {
                leading
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
            .frame(minHeight: Theme.Size.control + 8)
            .background {
                shape.fill(
                    isSelected ? Theme.Palette.violet.opacity(0.15)
                        : isHovering ? Theme.Palette.controlPressed : Theme.Palette.control
                )
            }
            .overlay {
                shape.strokeBorder(
                    isSelected ? Theme.Palette.violet.opacity(0.8) : Theme.Palette.hairline,
                    lineWidth: isSelected ? 1.5 : 1
                )
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// The "New worktree" choice, last in the list.
private struct NewWorktreeRow: View {
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
            RadioDot(isSelected: isSelected)
            PhIcon(Ph.plus, size: 16)
                .foregroundStyle(Theme.Palette.secondaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text("New worktree")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Palette.text)
                Text("Its own checkout and branch. Nothing touches your files until you merge.")
                    .font(.callout)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
        .frame(minHeight: 52)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous)
                .fill(isSelected ? Theme.Palette.violet.opacity(0.14) : .clear)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
    }
}

/// What the new worktree is called and cut from, and where it will go.
private struct NewWorktreePanel: View {
    let model: NewSessionModel

    @FocusState private var isBranchFocused: Bool

    private static let labelWidth: CGFloat = 90

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
            row("Branch") {
                TextField(
                    "Branch",
                    text: Binding(get: { model.branchName }, set: { model.editBranchName($0) }),
                    prompt: Text("agent/new-task").foregroundStyle(Theme.Palette.tertiaryText)
                )
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Theme.Palette.text)
                .focused($isBranchFocused)
                .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
                .frame(minHeight: Theme.Size.control + 6)
                .fieldSurface()
            }

            row("Based on") { BaseBranchPicker(model: model) }

            row("Folder") {
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(Theme.Palette.warning)
                } else if let location = model.location {
                    Text((location.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.head)
                } else {
                    Text("\u{2014}").foregroundStyle(Theme.Palette.tertiaryText)
                }
            }
        }
        .padding(Theme.Spacing.loose)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fieldGroupSurface()
        .task { isBranchFocused = true }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: Theme.Spacing.normal) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Palette.secondaryText)
                .frame(width: Self.labelWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                Text(model.baseBranch.isEmpty ? "\u{2014}" : model.baseBranch)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                PhIcon(Ph.caretUpDown, size: 12)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.control + 6)
            .fieldSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    PhIcon(Ph.checkBold, size: 12)
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
    /// Tall enough for a name and a path, which is what the list's height is
    /// counted in.
    static let height: CGFloat = 56

    let worktree: GitWorktree
    let isDefault: Bool
    let isActive: Bool
    let activity: WorktreeActivity
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.normal + Theme.Spacing.tight) {
            RadioDot(isSelected: isSelected)
            PhIcon(Ph.gitBranch, size: 16)
                .foregroundStyle(Theme.Palette.secondaryText)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.normal) {
                    Text(NewSessionModel.label(of: worktree))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.Palette.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isDefault { badge("default") }
                    if isActive { badge("current") }
                }
                Text((worktree.path.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: Theme.Spacing.normal)

            status
        }
        .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
        .frame(minHeight: Self.height - 2)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous)
                .fill(isSelected ? Theme.Palette.violet.opacity(0.14) : isHovering ? Theme.Palette.control : .clear)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: select)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.Palette.secondaryText)
            .padding(.horizontal, Theme.Spacing.normal - 1)
            .padding(.vertical, 1)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.Palette.control)
            }
    }

    private var status: some View {
        HStack(spacing: Theme.Spacing.normal - 2) {
            switch activity {
            case .working: Circle().fill(Theme.Palette.success).frame(width: 8, height: 8)
            case .waiting: Circle().fill(Theme.Palette.warning).frame(width: 8, height: 8)
            case .idle, .none: EmptyView()
            }
            Text(activity.label)
                .font(.system(size: 12))
                .foregroundStyle(activity == .none ? Theme.Palette.tertiaryText : Theme.Palette.secondaryText)
        }
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
