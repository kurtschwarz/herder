import Core
import DesignSystem
import SwiftUI

/// What a repository's sessions that have ended look like under its
/// worktrees: the latest few, by the day they ended, and how many there are
/// in all.
struct RepositoryHistory: View {
    let ended: [SessionHistoryRecord]

    /// The worktrees the repository has now, which is how a session whose
    /// worktree has gone is known.
    let worktrees: [GitWorktree]

    var body: some View {
        let digest = SessionHistoryDigest(ended: ended)
        // A stack even when empty, so what the section attaches to it, like
        // reading the history, still runs while there is nothing to show.
        VStack(alignment: .leading, spacing: 0) {
            if !digest.isEmpty {
                group("Today", digest.today)
                group("Yesterday", digest.yesterday)
                AllHistoryRow(count: digest.total)
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ records: [SessionHistoryRecord]) -> some View {
        if !records.isEmpty {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.tertiaryText)
                .padding(.top, Theme.Spacing.normal)
                .padding(.horizontal, Theme.Spacing.normal + 2)
            ForEach(records) { record in
                HistoryRow(record: record, worktreeExists: worktrees.contains { WorkspaceID($0.path) == record.worktree })
            }
        }
    }
}

/// One ended session: what it was called, and under that where it ran and how
/// long since it ended. Click to pick it up again.
private struct HistoryRow: View {
    let record: SessionHistoryRecord
    let worktreeExists: Bool

    @Environment(AgentCatalog.self) private var catalog: AgentCatalog?
    @Environment(\.resumeAgentSession) private var resume

    @State private var isHovering = false

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
                .fill(Theme.Palette.accent)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 1) {
                Text(record.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
                .fill(isHovering && reason == nil ? Theme.Palette.control : .clear)
        }
        .opacity(reason == nil ? 1 : 0.5)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { if reason == nil { resume(record) } }
        .pointerStyle(reason == nil ? .link : nil)
        .help(reason ?? "Resume in \(record.agentName)")
    }

    /// The branch it was on, and how long since it ended.
    private var detail: String {
        let age = record.endedAt.map { RelativeAge.short(from: $0) }
        return [record.branch ?? record.worktree.root.name, age].compactMap { $0 }.joined(separator: " \u{00B7} ")
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
