import Core
import DesignSystem
import SwiftUI

/// The sessions that have ended in every repository the workspace selector
/// has on show, together: the latest few, by the day they ended, and how many
/// there are in all.
struct SessionHistorySection: View {
    /// Where each shown repository's history is kept, and its worktrees now.
    let sources: [RepositoriesModel.HistorySource]

    @Environment(AgentSessions.self) private var history: AgentSessions?
    @Environment(WindowAgentSessions.self) private var open: WindowAgentSessions?
    @Environment(Workspace.self) private var active: Workspace?
    @Environment(\.renameAgentSession) private var renameAgentSession

    private var keys: [PathKey] { sources.map(\.key) }

    /// Every ended session in the shown repositories, latest end first, and
    /// which repository each is from when there is more than one to tell
    /// apart.
    private var ended: (records: [AgentSession], repositories: [UUID: String]) {
        guard let history else { return ([], [:]) }
        var records: [AgentSession] = []
        var repositories: [UUID: String] = [:]
        var seen: Set<PathKey> = []
        for source in sources where seen.insert(source.key).inserted {
            for record in history.ended(in: source.key) {
                records.append(record)
                if sources.count > 1 { repositories[record.id] = source.name }
            }
        }
        records.sort { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
        return (records, repositories)
    }

    /// The worktrees that are still there, across them all.
    private var worktrees: Set<WorkspaceID> {
        sources.reduce(into: []) { $0.formUnion($1.worktrees) }
    }

    var body: some View {
        let ended = ended
        let digest = SessionHistoryDigest(ended: ended.records)
        // A stack even when empty, so reading the history, attached to it,
        // still runs while there is nothing to show.
        VStack(alignment: .leading, spacing: 0) {
            if !digest.isEmpty {
                group("Today", digest.today, repositories: ended.repositories)
                group("Yesterday", digest.yesterday, repositories: ended.repositories)
                AllHistoryRow(count: digest.total)
            }
        }
        .backgroundPreferenceValue(HistoryDotCenters.self) { centers in
            GeometryReader { proxy in
                let points = centers.map { proxy[$0] }
                if let first = points.min(by: { $0.y < $1.y }),
                   let last = points.max(by: { $0.y < $1.y }),
                   first.y < last.y
                {
                    Path { path in
                        path.move(to: first)
                        path.addLine(to: CGPoint(x: first.x, y: last.y))
                    }
                    .stroke(Theme.Palette.hairline, lineWidth: 1)
                }
            }
        }
        .task(id: keys) {
            guard let history else { return }
            for key in keys { await history.load(key) }
        }
    }

    @ViewBuilder
    private func group(
        _ title: String,
        _ records: [AgentSession],
        repositories: [UUID: String]
    ) -> some View {
        if !records.isEmpty {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.tertiaryText)
                .padding(.top, Theme.Spacing.normal)
                .padding(.horizontal, Theme.Spacing.normal + 2)
            ForEach(records) { record in
                HistoryRow(
                    record: record,
                    repository: repositories[record.id],
                    worktreeExists: worktrees.contains(record.worktree),
                    isSelected: active?.id == record.worktree && open?.focused == record.id,
                    canDelete: history?.isOpen(record.id) != true,
                    rename: {
                        history?.rename(record.id, to: $0)
                        // Its tab, if it is open to be read, shows the new name.
                        renameAgentSession(record, to: $0)
                    },
                    delete: { history?.delete(record.id) }
                )
            }
        }
    }
}

/// Where each row's dot is, so the list can draw one line through them all.
private struct HistoryDotCenters: PreferenceKey {
    static let defaultValue: [Anchor<CGPoint>] = []

    static func reduce(value: inout [Anchor<CGPoint>], nextValue: () -> [Anchor<CGPoint>]) {
        value.append(contentsOf: nextValue())
    }
}

/// One ended session: what it was called, and under that where it ran and how
/// long since it ended. Click to pick it up again; right click to rename or
/// delete it.
private struct HistoryRow: View {
    let record: AgentSession

    /// The repository it ran in, when more than one is on show.
    let repository: String?

    let worktreeExists: Bool

    /// Its tab is the one in front.
    let isSelected: Bool

    /// Whether no window has a tab open for it.
    let canDelete: Bool
    let rename: (String) -> Void
    let delete: () -> Void

    @Environment(AgentCatalog.self) private var catalog: AgentCatalog?
    @Environment(\.resumeAgentSession) private var resume

    @State private var isHovering = false
    @State private var isRenaming = false

    /// Why it cannot be picked up again, or `nil` when it can. Never a
    /// stand-in: the last session in the worktree may be another.
    private var unavailable: String? {
        if !worktreeExists { return "Its worktree is gone" }
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
                .anchorPreference(key: HistoryDotCenters.self, value: .center) { [$0] }
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
        .onTapGesture { if reason == nil, !isRenaming { resume(record) } }
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

/// The way into the whole history, with how much there is. Its view is not
/// built yet, so for now it only counts.
private struct AllHistoryRow: View {
    let count: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.normal + 2) {
            Image(systemName: "clock.arrow.circlepath")
                .frame(width: 8)
            Text("All history")
                .font(.system(size: 13))
            Spacer(minLength: 0)
            Text("\(count)")
                .font(.system(size: 12))
        }
        .foregroundStyle(Theme.Palette.secondaryText)
        .padding(.horizontal, Theme.Spacing.normal + 2)
        .padding(.vertical, Theme.Spacing.normal)
    }
}
