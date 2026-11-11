import Core
import DesignSystem
import SwiftUI

/// The strip over the screen: what the session in front is, where it is
/// working, and how much its worktree has changed. Switching between sessions
/// is the sidebar's.
struct AgentHeader: View {
    let model: AgentPanelModel

    @State private var isRenaming = false

    var body: some View {
        HStack(spacing: Theme.Spacing.normal + 2) {
            if let tab = model.activeTab {
                glyph
                VStack(alignment: .leading, spacing: 2) {
                    subject(of: tab)
                    HStack(spacing: Theme.Spacing.tight + 2) {
                        branch
                        Text("\u{00B7}")
                        AgentStateDot(tab.state)
                        elapsed(since: tab.startedAt)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.tertiaryText)
                }
            } else {
                branch
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.secondaryText)
            }

            Spacer(minLength: Theme.Spacing.normal)

            if let changes = model.workspace?.changes {
                ChangeChip(changes: changes)
            }
            if let tab = model.activeTab {
                menu(for: tab)
            }
        }
        .padding(.horizontal, Theme.Spacing.normal + 2)
        .padding(.vertical, Theme.Spacing.normal)
    }

    private var glyph: some View {
        PhIcon(Ph.sparkleFill, size: 14)
            .foregroundStyle(Theme.Palette.violet)
            .frame(width: 28, height: 28)
            .background(
                Theme.Palette.violet.opacity(0.16),
                in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            )
    }

    @ViewBuilder
    private func subject(of tab: AgentTab) -> some View {
        if isRenaming {
            AgentRenameField(name: model.subject(of: tab)) { name in
                isRenaming = false
                // Escape and a cleared field both say blank, which would drop
                // the name the person gave it: neither is a rename.
                if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { model.rename(tab, to: name) }
            }
        } else {
            Text(model.subject(of: tab))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Palette.text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var branch: some View {
        if let checkout = model.workspace?.checkout {
            HStack(spacing: Theme.Spacing.tight) {
                PhIcon(Ph.gitBranch, size: 10)
                switch checkout {
                case .branch(let name):
                    Text(name)
                case .detached(let sha):
                    Text(sha).font(.system(size: 11, design: .monospaced))
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private func elapsed(since started: Date?) -> some View {
        if let started {
            // Redrawn on its own every half minute, so "now" becomes "1m"
            // without anything else changing.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(RelativeAge.short(from: started, now: context.date))
            }
        } else {
            Text("now")
        }
    }

    private func menu(for tab: AgentTab) -> some View {
        Menu {
            Menu("New Session") {
                ForEach(model.catalog.agents.filter(\.isRunnable)) { agent in
                    Button(agent.displayName) { Task { await model.startSession(agent) } }
                }
            }
            .disabled(model.workspace == nil)
            Button("Rename") { isRenaming = true }
            Divider()
            Button("Close") { model.close(tab) }
        } label: {
            HoverIconLabel(icon: Ph.dotsThree)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
