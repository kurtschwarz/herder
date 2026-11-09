import Core
import DesignSystem
import SwiftUI

/// The agents a session can be started with: the presets, which are fixed, and
/// the user's own, which are a name and a command each.
struct AgentsSettings: View {
    let catalog: AgentCatalog

    var body: some View {
        SettingsPaneContent(pane: .agents) {
            Text("Each agent is a command run in your login shell, in the root of the worktree a session starts in. The resume command picks a session up again after its window was closed; without one, it starts afresh. \(Agent.sessionToken) in either stands for the session\u{2019}s id: one Herder makes up, or, for an agent that names its own sessions, the one its session lookup finds.")
                .font(.callout)
                .foregroundStyle(Theme.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            SettingsSection("Built in") {
                ForEach(Agent.presets) { agent in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.loose) {
                        Text(agent.name)
                            .foregroundStyle(Theme.Palette.text)
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(agent.command)
                            if let resume = agent.resumeCommand {
                                Text(resume).foregroundStyle(Theme.Palette.tertiaryText)
                            }
                            if let lookup = agent.sessionLookup {
                                Text(lookup).foregroundStyle(Theme.Palette.tertiaryText)
                            }
                        }
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .textSelection(.enabled)
                    }
                    .padding(.vertical, Theme.Spacing.tight)
                }
            }

            SettingsSection("Your agents") {
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
}

/// One of the user's agents, edited in place. Each change is saved as it is
/// typed: the list is small, and there is no "Save" to forget.
private struct CustomAgentRow: View {
    let agent: Agent
    let catalog: AgentCatalog

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.normal) {
            TextField("Name", text: binding(\.name))
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.Palette.text)
                .padding(.horizontal, Theme.Spacing.normal)
                .frame(width: 160, height: Theme.Size.control)
                .fieldSurface()

            VStack(spacing: Theme.Spacing.tight) {
                commandField("Command, e.g. aider --model sonnet", text: binding(\.command))
                commandField("Resume command (optional), e.g. aider --restore-chat-history", text: optionalBinding(\.resumeCommand))
                commandField("Session lookup (optional), lists the agent\u{2019}s sessions", text: optionalBinding(\.sessionLookup))
            }

            HoverIconButton(icon: Ph.trash, help: "Remove \(agent.displayName)") {
                catalog.remove(agent.id)
            }
        }
        .padding(.vertical, Theme.Spacing.tight)
    }

    private func commandField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Theme.Palette.text)
            .padding(.horizontal, Theme.Spacing.normal)
            .frame(height: Theme.Size.control)
            .fieldSurface()
    }

    /// Blank means none.
    private func optionalBinding(_ field: WritableKeyPath<Agent, String?>) -> Binding<String> {
        Binding(
            get: { catalog.agent(agent.id)?[keyPath: field] ?? "" },
            set: { value in
                guard var current = catalog.agent(agent.id) else { return }
                current[keyPath: field] = value.trimmingCharacters(in: .whitespaces).isEmpty ? nil : value
                catalog.update(current)
            }
        )
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
