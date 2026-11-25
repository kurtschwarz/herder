import Core
import DesignSystem
import SwiftUI

/// The variables set for one custom agent's terminal, as rows of a name and a
/// value. Each change is saved as it is typed, like the rest of the agent's row.
///
/// The rows are kept here, not read back from the agent, because a row being
/// typed may have no name yet or share one: see ``EnvironmentVariable``.
struct EnvironmentEditor: View {
    let agentID: Agent.ID
    let catalog: AgentCatalog
    @State private var rows: [EnvironmentVariable]

    init(agent: Agent, catalog: AgentCatalog) {
        agentID = agent.id
        self.catalog = catalog
        _rows = State(initialValue: EnvironmentVariable.rows(from: agent.environment))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            ForEach($rows) { $row in
                VStack(spacing: Theme.Spacing.tight) {
                    HStack(spacing: Theme.Spacing.tight) {
                        field("NAME", text: $row.name)
                            .foregroundStyle(
                                row.name.isEmpty || row.hasValidName ? Theme.Palette.text : Theme.Palette.warning
                            )
                        HoverIconButton(icon: Ph.trash, help: "Remove \(row.name.isEmpty ? "variable" : row.name)") {
                            rows.removeAll { $0.id == row.id }
                        }
                    }
                    field("value", text: $row.value)
                }
                .padding(.bottom, Theme.Spacing.tight)
            }
            Button("Add Variable") { rows.append(EnvironmentVariable(name: "", value: "")) }
                .buttonStyle(.secondary)
        }
        .onChange(of: rows) { save() }
        // A change from `settings.json`. One the rows made themselves reads
        // back as what they already set, and leaves a half-typed row alone.
        .onChange(of: catalog.agent(agentID)?.environment) { _, environment in
            guard EnvironmentVariable.dictionary(from: rows) != environment else { return }
            rows = EnvironmentVariable.rows(from: environment)
        }
    }

    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, Theme.Spacing.normal)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.control)
            .fieldSurface()
    }

    private func save() {
        guard var current = catalog.agent(agentID) else { return }
        current.environment = EnvironmentVariable.dictionary(from: rows)
        catalog.update(current)
    }
}
