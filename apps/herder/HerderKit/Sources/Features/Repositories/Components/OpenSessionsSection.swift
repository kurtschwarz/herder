import Core
import DesignSystem
import SwiftUI

/// The agent sessions open in this window in any worktree of the repositories
/// on show, together, each saying which worktree it is in; and the way to
/// start another.
struct OpenSessionsSection: View {
    let model: RepositoriesModel

    /// The repositories the workspace selector has on show.
    let repositories: [Repository]

    /// What the agent panel has open. Absent outside a window, which is what
    /// lets the previews render without one.
    @Environment(OpenAgentSessions.self) private var open: OpenAgentSessions?
    @Environment(Workspace.self) private var active: Workspace?
    @Environment(\.showAgentSession) private var showAgentSession

    var body: some View {
        let labels = model.worktreeLabels(of: repositories)
        let sessions = open?.sessions.filter { labels[$0.workspace] != nil } ?? []
        VStack(alignment: .leading, spacing: 0) {
            header(count: sessions.count)

            ForEach(repositories.filter { !$0.isAvailable }) { repository in
                notice("\(repository.name) can\u{2019}t be reached", help: repository.path)
            }
            ForEach(repositories.filter { model.listings[$0.id] == .unreadable }) { repository in
                notice("Couldn\u{2019}t read \(repository.name)\u{2019}s worktrees", help: repository.path)
            }

            ForEach(sessions) { session in
                AgentSessionRow(
                    session: session,
                    branch: labels[session.workspace] ?? session.workspace.root.name,
                    isSelected: active?.id == session.workspace && open?.focused == session.id
                ) { showAgentSession(session) }
            }

            if sessions.isEmpty {
                Text("No sessions running")
                    .font(.callout)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .padding(.horizontal, Theme.Spacing.normal + 2)
                    .padding(.vertical, Theme.Spacing.tight)
            }
        }
    }

    private func header(count: Int) -> some View {
        HStack(spacing: Theme.Spacing.normal) {
            Text("WORKING & WAITING")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(Theme.Palette.tertiaryText)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Circle().fill(Theme.Palette.control))
            }
            Spacer(minLength: 0)
            newSessionButton
        }
        .padding(.horizontal, Theme.Spacing.normal + 2)
        .padding(.vertical, Theme.Spacing.tight)
    }

    /// One repository on show starts a session in it; with more, the menu
    /// asks which.
    @ViewBuilder
    private var newSessionButton: some View {
        let available = repositories.filter(\.isAvailable)
        if available.count == 1 {
            Button { model.beginNewSession(in: available[0]) } label: {
                PhIcon(Ph.plus, size: 12)
            }
            .buttonStyle(.icon(size: 20))
            .help("New session in \(available[0].name)")
        } else {
            Menu {
                ForEach(available) { repository in
                    Button(repository.name) { model.beginNewSession(in: repository) }
                }
            } label: {
                HoverIconLabel(icon: Ph.plus, iconSize: 12, side: 20, radius: 6)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(available.isEmpty)
            .help("New session")
        }
    }

    private func notice(_ text: String, help: String) -> some View {
        HStack(spacing: Theme.Spacing.normal) {
            PhIcon(Ph.warningFill, size: 12)
                .foregroundStyle(Theme.Palette.warning)
            Text(text)
                .font(.callout)
                .foregroundStyle(Theme.Palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, Theme.Spacing.normal + 2)
        .padding(.vertical, Theme.Spacing.tight)
        .help(help)
    }
}

/// One session: what it is called and how long since it last did anything,
/// under that what it seems to be doing, and the worktree it is in.
private struct AgentSessionRow: View {
    let session: AgentSessionSummary
    let branch: String
    let isSelected: Bool
    let show: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.normal + 2) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.normal) {
                    Text(session.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    // Redrawn on its own every half minute, so "now"
                    // becomes "1m" without anything else changing.
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(RelativeAge.short(from: session.lastActivity, now: context.date))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.tertiaryText)
                    }
                }
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(isUrgent ? Theme.Palette.warning : Theme.Palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: Theme.Spacing.tight) {
                    PhIcon(Ph.gitBranch, size: 10)
                    Text(branch)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.tertiaryText)
            }
        }
        .padding(.horizontal, Theme.Spacing.normal + 2)
        .padding(.vertical, Theme.Spacing.normal - 2)
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            shape
                .fill(isSelected || isHovering ? Theme.Palette.control : .clear)
                .overlay { shape.strokeBorder(Theme.Palette.violet.opacity(isSelected ? 0.7 : 0), lineWidth: 1) }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: show)
        .pointerStyle(.link)
        .help(session.agentName)
    }

    private var isUrgent: Bool {
        if case .needsInput = session.state { true } else { false }
    }

    private var dotColor: Color {
        switch session.state {
        case .working: Theme.Palette.success
        case .needsInput: Theme.Palette.warning
        case .exited(let code) where code != 0: Theme.Palette.danger
        case .failed: Theme.Palette.danger
        case .paused, .starting, .idle, .exited: Theme.Palette.tertiaryText
        }
    }

    /// The second line: the agent, and what it seems to be up to.
    private var summary: String {
        switch session.state {
        case .paused: "\(session.agentName) \u{00B7} Resumes when opened"
        case .starting: "\(session.agentName) \u{00B7} Starting"
        case .working: "\(session.agentName) \u{00B7} Working"
        case .needsInput(let detail): detail.map { "Needs input \u{00B7} \($0)" } ?? "Needs input"
        case .idle: "\(session.agentName) \u{00B7} Idle"
        case .exited(let code): "\(session.agentName) \u{00B7} Exited (\(code))"
        case .failed: "\(session.agentName) \u{00B7} Couldn\u{2019}t start"
        }
    }
}
