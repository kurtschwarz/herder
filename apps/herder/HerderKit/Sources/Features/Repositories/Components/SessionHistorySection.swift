import Core
import DesignSystem
import SwiftUI

/// The sessions that have ended in every repository the workspace selector
/// has on show, together: the latest few, by the day they ended, and how many
/// there are in all.
struct SessionHistorySection: View {
    /// Where each shown repository's history is kept, and its worktrees now.
    let sources: [RepositoriesModel.HistorySource]

    /// Whether every ended session is listed, rather than the latest few.
    @Binding var isExpanded: Bool

    @Environment(AgentSessions.self) private var history: AgentSessions?
    @Environment(WindowAgentSessions.self) private var open: WindowAgentSessions?
    @Environment(Workspace.self) private var active: Workspace?
    @Environment(\.renameAgentSession) private var renameAgentSession

    private var keys: [PathKey] { sources.map(\.key) }

    /// Every ended session in the shown repositories, latest end first, which
    /// repository each is from when there is more than one to tell apart, and
    /// the worktree each is picked up in: its own, else its repository's
    /// fallback. None has no entry.
    private var ended: (records: [AgentSession], repositories: [UUID: String], targets: [UUID: WorkspaceID]) {
        guard let history else { return ([], [:], [:]) }
        var records: [AgentSession] = []
        var repositories: [UUID: String] = [:]
        var targets: [UUID: WorkspaceID] = [:]
        var seen: Set<PathKey> = []
        for source in sources where seen.insert(source.key).inserted {
            for record in history.ended(in: source.key) {
                records.append(record)
                targets[record.id] = source.worktrees.contains(record.worktree) ? record.worktree : source.fallback
                if sources.count > 1 { repositories[record.id] = source.name }
            }
        }
        records.sort { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
        return (records, repositories, targets)
    }

    /// The id the sidebar scrolls to, to keep "All history" in view.
    static let footerID = "all-history"

    /// A section of the sidebar's lazy stack, so its rows are built as they
    /// scroll into view and "All history" can pin to the bottom of the sidebar.
    var body: some View {
        let ended = ended
        let digest = SessionHistoryDigest(ended: ended.records, isExpanded: isExpanded)
        let last = digest.groups.last?.sessions.last?.id
        Section {
            ForEach(Array(digest.groups.enumerated()), id: \.element.title) { index, group in
                HistoryGroupHeader(title: group.title, drawsLine: index > 0)
                ForEach(group.sessions) { record in
                    HistoryRow(
                        record: record,
                        repository: ended.repositories[record.id],
                        target: ended.targets[record.id],
                        isSelected: active?.id == record.worktree && open?.focused == record.id,
                        canDelete: history?.isOpen(record.id) != true,
                        startsLine: index == 0 && record.id == group.sessions.first?.id,
                        endsLine: record.id == last,
                        rename: {
                            history?.rename(record.id, to: $0)
                            // Its tab, if it is open to be read, shows the new name.
                            renameAgentSession(record, to: $0)
                        },
                        delete: { history?.delete(record.id) }
                    )
                }
            }
        } footer: {
            // Present even when empty, so reading the history, attached to
            // it, still runs while there is nothing to show.
            Group {
                if digest.isEmpty {
                    Color.clear.frame(height: 0)
                } else {
                    AllHistoryRow(count: digest.total, isExpanded: $isExpanded)
                        .id(Self.footerID)
                }
            }
            .task(id: keys) {
                guard let history else { return }
                for key in keys { await history.load(key) }
            }
        }
    }
}

/// Draws the part of the line through the history dots that falls in this
/// row or header. Each draws its own, so the line has no need of a stack that
/// wraps them all and the rows can be built lazily.
private struct HistoryLine: ViewModifier {
    /// Where the first row's dot is below its top, which is where the line
    /// starts, and likewise where the last row's ends.
    static let dotY = Theme.Spacing.normal - 2 + 5 + 4
    static let x = Theme.Spacing.normal + 2 + 4 - 0.5

    var isDrawn = true
    let startsAtDot: Bool
    let endsAtDot: Bool

    func body(content: Content) -> some View {
        content.background(alignment: .topLeading) {
            if isDrawn {
                GeometryReader { proxy in
                    // A point past each end, to close the gap the stack leaves
                    // between one row and the next.
                    let top = startsAtDot ? Self.dotY : -1
                    let bottom = endsAtDot ? Self.dotY : proxy.size.height + 1
                    Theme.Palette.hairline
                        .frame(width: 1, height: max(bottom - top, 0))
                        .offset(x: Self.x, y: top)
                }
            }
        }
    }
}

private struct HistoryGroupHeader: View {
    let title: String

    /// Whether the line runs through, from the group above to the one below.
    let drawsLine: Bool

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.Palette.tertiaryText)
            .padding(.top, Theme.Spacing.normal)
            .padding(.horizontal, Theme.Spacing.normal + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(HistoryLine(isDrawn: drawsLine, startsAtDot: false, endsAtDot: false))
    }
}

/// One ended session: what it was called, and under that where it ran and how
/// long since it ended. Click to pick it up again; right click to rename or
/// delete it.
private struct HistoryRow: View {
    let record: AgentSession

    /// The repository it ran in, when more than one is on show.
    let repository: String?

    /// The worktree it is picked up in, or `nil` when there is none.
    let target: WorkspaceID?

    /// Its tab is the one in front.
    let isSelected: Bool

    /// Whether no window has a tab open for it.
    let canDelete: Bool

    /// Whether the line through the dots starts or ends at this row's, rather
    /// than running on past it.
    let startsLine: Bool
    let endsLine: Bool
    let rename: (String) -> Void
    let delete: () -> Void

    @Environment(AgentCatalog.self) private var catalog: AgentCatalog?
    @Environment(\.resumeAgentSession) private var resume

    @State private var isHovering = false
    @State private var isRenaming = false

    /// Why it cannot be picked up again, or `nil` when it can. Never a
    /// stand-in: the last session in the worktree may be another.
    private var unavailable: String? {
        if target == nil { return "Its worktree is gone, and the repository has none to open it in" }
        guard let agent = catalog?.agent(record.agentID), agent.isRunnable else {
            return "\(record.agentName) is no longer set up"
        }
        if record.sessionID == nil { return "\(record.agentName) gave no session id to resume it by" }
        return nil
    }

    var body: some View {
        let reason = unavailable
        HStack(alignment: .top, spacing: Theme.Spacing.normal + 2) {
            Circle()
                .fill(Theme.Palette.tertiaryText)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 1) {
                if isRenaming {
                    RenameField(name: record.title, weight: .regular) { name in
                        isRenaming = false
                        rename(name)
                    }
                } else {
                    Text(record.title)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Palette.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                HStack(spacing: Theme.Spacing.tight) {
                    Ph.gitBranch
                        .resizable()
                        .scaledToFit()
                        .frame(width: 10, height: 10)
                    Text(detail)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.tertiaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.normal + 2)
        .padding(.vertical, Theme.Spacing.normal - 2)
        .modifier(HistoryLine(startsAtDot: startsLine, endsAtDot: endsLine))
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(isSelected || (isHovering && reason == nil && !isRenaming) ? Theme.Palette.control : .clear)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .strokeBorder(Theme.Palette.violet.opacity(isSelected ? 0.7 : 0), lineWidth: 1)
                }
        }
        .opacity(reason == nil || isRenaming ? 1 : 0.5)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { if reason == nil, !isRenaming, let target { resume(record, in: target) } }
        .pointerStyle(reason == nil && !isRenaming ? .link : nil)
        .help(reason ?? "Resume in \(record.agentName)")
        .contextMenu {
            Button("Rename") { isRenaming = true }

            Divider()

            Button("Delete", role: .destructive, action: delete)
                .disabled(!canDelete)
        }
    }

    /// The repository when that needs saying, the branch it was on, and how
    /// long since it ended.
    private var detail: String {
        let branch = record.branch ?? record.worktree.root.name
        let age = record.endedAt.map { RelativeAge.short(from: $0) }
        return [repository.map { "\($0)/\(branch)" } ?? branch, age]
            .compactMap { $0 }
            .joined(separator: " \u{00B7} ")
    }
}

/// How much history there is, and the toggle between the latest few and all
/// of it. It is the section's footer, so it pins to the bottom of the sidebar
/// while there is more history than fits, and its own fill keeps the rows
/// scrolling under it from showing through.
private struct AllHistoryRow: View {
    let count: Int
    @Binding var isExpanded: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.normal + 2) {
            Image(systemName: "clock.arrow.circlepath")
                .frame(width: 8)
            Text("All history")
                .font(.system(size: 13))
            Spacer(minLength: 0)
            Text("\(count)")
                .font(.system(size: 12))
            PhIcon(Ph.caretDownBold, size: 10)
                .rotationEffect(.degrees(isExpanded ? 180 : -90))
                .animation(.easeOut(duration: 0.15), value: isExpanded)
        }
        .foregroundStyle(Theme.Palette.secondaryText)
        .padding(.horizontal, Theme.Spacing.normal + 2)
        .padding(.vertical, Theme.Spacing.normal)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(isHovering ? Theme.Palette.control : .clear)
        }
        .background {
            // Past the stack's own inset, so nothing shows beside the row.
            Theme.Palette.window.padding(.horizontal, -Theme.Spacing.tight)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { isExpanded.toggle() }
        .pointerStyle(.link)
        .help(isExpanded ? "Show less" : "Show all history")
    }
}
