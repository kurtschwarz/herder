import Core
import SwiftUI

/// A button that starts an agent session: a click starts the agent used last,
/// and holding it, or its menu, offers the others.
///
/// One view because the sidebar, the agent panel and the empty panel all offer
/// the same choice, and should offer it the same way.
public struct AgentStartMenu<Label: View>: View {
    private let catalog: AgentCatalog
    private let start: (Agent) -> Void
    private let label: Label

    public init(catalog: AgentCatalog, start: @escaping (Agent) -> Void, @ViewBuilder label: () -> Label) {
        self.catalog = catalog
        self.start = start
        self.label = label()
    }

    public var body: some View {
        Menu {
            ForEach(catalog.agents.filter(\.isRunnable)) { agent in
                Button(agent.displayName) { start(agent) }
            }
        } label: {
            label
        } primaryAction: {
            start(catalog.lastUsed)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Start \(catalog.lastUsed.displayName). Hold for other agents.")
    }
}
