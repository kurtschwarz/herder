import Core
import DesignSystem
import SwiftUI

/// The agent sessions open in this window for one worktree, under its row.
struct WorktreeAgentSessions: View {
    let workspace: WorkspaceID

    /// What the agent panel has open. Absent outside a window, which is what
    /// lets the previews render without one.
    @Environment(OpenAgentSessions.self) private var open: OpenAgentSessions?
    @Environment(Workspace.self) private var active: Workspace?
    @Environment(\.showAgentSession) private var showAgentSession

    var body: some View {
        if let open {
            ForEach(open.sessions(in: workspace)) { session in
                AgentSessionRow(
                    session: session,
                    isSelected: active?.id == workspace && open.focused == session.id
                ) { showAgentSession(session) }
            }
        }
    }
}

/// One session: what it is called and how long since it last did anything,
/// and under that what it seems to be doing.
private struct AgentSessionRow: View {
    let session: AgentSessionSummary
    let isSelected: Bool
    let show: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            // The worktree's guide line, carried on past its row.
            Rectangle()
                .fill(Theme.Palette.hairline)
                .frame(width: 1)
                .padding(.leading, Theme.Spacing.normal + Theme.Size.chevron / 2)

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
            .padding(.leading, Theme.Spacing.normal)
            .padding(.vertical, 1)
        }
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
        case .starting, .idle, .exited: Theme.Palette.tertiaryText
        }
    }

    /// The second line: the agent, and what it seems to be up to.
    private var summary: String {
        switch session.state {
        case .starting: "\(session.agentName) \u{00B7} Starting"
        case .working: "\(session.agentName) \u{00B7} Working"
        case .needsInput(let detail): detail.map { "Needs input \u{00B7} \($0)" } ?? "Needs input"
        case .idle: "\(session.agentName) \u{00B7} Idle"
        case .exited(let code): "\(session.agentName) \u{00B7} Exited (\(code))"
        case .failed: "\(session.agentName) \u{00B7} Couldn\u{2019}t start"
        }
    }
}
