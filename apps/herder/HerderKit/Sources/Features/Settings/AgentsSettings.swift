import Core
import DesignSystem
import PhosphorSwift
import SwiftUI

/// The agents a session can be started with: the presets, which are fixed, and
/// the user's own, which are a name and a command each.
struct AgentsSettings: View {
    let catalog: AgentCatalog

    var body: some View {
        SettingsPaneContent(pane: .agents) {
            Text("Each agent is a command run in your login shell, in the root of the worktree a session starts in.")
                .font(.callout)
                .foregroundStyle(Theme.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            section("Built in") {
                ForEach(Agent.presets) { agent in
                    HStack(spacing: Theme.Spacing.loose) {
                        Text(agent.name)
                            .foregroundStyle(Theme.Palette.text)
                        Spacer(minLength: 0)
                        Text(agent.command)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                    .padding(.vertical, Theme.Spacing.tight)
                }
            }

            section("Your agents") {
                if catalog.custom.isEmpty {
                    Text("None yet.")
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .padding(.vertical, Theme.Spacing.tight)
                }
                ForEach(catalog.custom) { agent in
                    CustomAgentRow(agent: agent, catalog: catalog)
                }
                Button("Add Agent") { catalog.add() }
                    .buttonStyle(.secondary)
                    .padding(.top, Theme.Spacing.tight)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.normal) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.secondaryText)
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                content()
            }
            .padding(Theme.Spacing.loose)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fieldGroupSurface()
        }
    }
}

/// One of the user's agents, edited in place. Each change is saved as it is
/// typed: the list is small, and there is no "Save" to forget.
private struct CustomAgentRow: View {
    let agent: Agent
    let catalog: AgentCatalog

    var body: some View {
        HStack(spacing: Theme.Spacing.normal) {
            TextField("Name", text: binding(\.name))
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.Palette.text)
                .padding(.horizontal, Theme.Spacing.normal)
                .frame(width: 160, height: Theme.Size.control)
                .fieldSurface()

            TextField("Command, e.g. aider --model sonnet", text: binding(\.command))
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.Palette.text)
                .padding(.horizontal, Theme.Spacing.normal)
                .frame(height: Theme.Size.control)
                .fieldSurface()

            HoverIconButton(icon: Ph.trash.regular, help: "Remove \(agent.displayName)") {
                catalog.remove(agent.id)
            }
        }
        .padding(.vertical, Theme.Spacing.tight)
    }

    private func binding(_ field: WritableKeyPath<Agent, String>) -> Binding<String> {
        Binding(
            get: { catalog.agent(agent.id)?[keyPath: field] ?? "" },
            set: { value in
                guard var current = catalog.agent(agent.id) else { return }
                current[keyPath: field] = value
                catalog.update(current)
            }
        )
    }
}
