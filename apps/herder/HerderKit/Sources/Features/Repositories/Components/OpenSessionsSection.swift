import Core
import DesignSystem
import SwiftUI

/// The agent sessions open in this window in any worktree of the repositories
/// on show, together, each saying which worktree it is in.
struct OpenSessionsSection: View {
    let model: RepositoriesModel

    /// The repositories the workspace selector has on show.
    let repositories: [Repository]

    /// What this window has open. Absent outside a window, which is what
    /// lets the previews render without one.
    @Environment(WindowAgentSessions.self) private var open: WindowAgentSessions?
    @Environment(Workspace.self) private var active: Workspace?
    @Environment(\.showAgentSession) private var showAgentSession
    @Environment(\.renameAgentSession) private var renameAgentSession
    @Environment(\.closeAgentSession) private var closeAgentSession

    /// The order the list was in when the pointer came onto it, while it is
    /// there. A session that starts meanwhile goes to the top.
    @State private var heldOrder: [UUID]?

    private func held(_ sessions: [AgentSession]) -> [AgentSession] {
        guard let heldOrder else { return sessions }
        let rank = Dictionary(heldOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return sessions.enumerated()
            .sorted { lhs, rhs in
                let (a, b) = (rank[lhs.element.id] ?? -1, rank[rhs.element.id] ?? -1)
                return a != b ? a < b : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    var body: some View {
        let labels = model.worktreeLabels(of: repositories)
        let sessions = held(open?.sessionsByRecency.filter { labels[$0.worktree] != nil } ?? [])
        let focused = open?.focused
        VStack(alignment: .leading, spacing: 0) {
            header(count: sessions.count)

            ForEach(repositories.filter { !$0.isAvailable }) { repository in
                notice("\(repository.name) can\u{2019}t be reached", help: repository.path)
            }
            ForEach(repositories.filter { model.listings[$0.id] == .unreadable }) { repository in
                notice("Couldn\u{2019}t read \(repository.name)\u{2019}s worktrees", help: repository.path)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(sessions) { session in
                    AgentSessionRow(
                        session: session,
                        branch: labels[session.worktree] ?? session.worktree.root.name,
                        isSelected: active?.id == session.worktree && focused == session.id,
                        show: { showAgentSession(session) },
                        rename: { renameAgentSession(session, to: $0) },
                        close: { closeAgentSession(session) }
                    )
                }
            }
            .animation(.default, value: sessions.map(\.id))
            // Rows hold still under the pointer, so one never moves away
            // from a click, and catch up when it leaves.
            .onHover { heldOrder = $0 ? sessions.map(\.id) : nil }
        }
    }

    private func header(count: Int) -> some View {
        HStack(spacing: Theme.Spacing.normal) {
            Text("WORKING & WAITING")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(Theme.Palette.tertiaryText)
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.secondaryText)
                .frame(minWidth: 18, minHeight: 18)
                .background(Circle().fill(Theme.Palette.control))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.normal + 2)
        .padding(.vertical, Theme.Spacing.tight)
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
/// under that what it seems to be doing, and the worktree it is in. Right
/// click to rename or close it, or hover for an X that closes it.
private struct AgentSessionRow: View {
    let session: AgentSession
    let branch: String
    let isSelected: Bool
    let show: () -> Void
    let rename: (String) -> Void
    let close: () -> Void

    @State private var isHovering = false
    @State private var isRenaming = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.normal + 2) {
            AgentStateDot(state)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.normal) {
                    if isRenaming {
                        RenameField(name: session.title) { name in
                            isRenaming = false
                            // Escape and a cleared field both say blank:
                            // neither is a name, and the panel would take
                            // it as one to drop.
                            if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { rename(name) }
                        }
                    } else {
                        Text(session.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                    // Redrawn on its own every half minute, so "now"
                    // becomes "1m" without anything else changing.
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(RelativeAge.short(from: lastActivity, now: context.date))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.tertiaryText)
                            // Wide enough for the X, which is laid over the
                            // age rather than swapped for it, so the row's
                            // size and the title's truncation stay put.
                            .frame(minWidth: 20)
                            .opacity(showsClose ? 0 : 1)
                            .overlay {
                                if showsClose {
                                    Button(action: close) {
                                        PhIcon(Ph.xBold, size: 10)
                                    }
                                    .buttonStyle(.icon(size: 20))
                                    .help("Close session")
                                }
                            }
                    }
                }
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(isUrgent ? Theme.Palette.warning : Theme.Palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: Theme.Spacing.normal) {
                    HStack(spacing: Theme.Spacing.tight) {
                        PhIcon(Ph.gitBranch, size: 10)
                        Text(branch)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    if let pullRequest = session.pullRequest {
                        PullRequestBadge(pullRequest)
                    }
                }
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
        .onTapGesture { if !isRenaming { show() } }
        .pointerStyle(isRenaming ? nil : .link)
        .help(session.agentName)
        .contextMenu {
            Button("Rename") { isRenaming = true }
            Divider()
            Button("Close", action: close)
        }
    }

    /// Every session listed here has a tab open; paused is what one would
    /// be if the store said nothing.
    private var state: AgentSession.State { session.state ?? .paused }

    private var showsClose: Bool { isHovering && !isRenaming }

    private var lastActivity: Date { session.live?.lastActivity ?? session.lastSeenAt }

    private var isUrgent: Bool {
        if case .needsInput = state { true } else { false }
    }

    /// The second line: the agent, and what it seems to be up to.
    private var summary: String {
        switch state {
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
