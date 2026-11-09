import Core
import DesignSystem
import PhosphorSwift
import SwiftUI

/// The strip over the screen: a tab for each open session, and a button for
/// another.
struct AgentHeader: View {
    let model: AgentPanelModel

    var body: some View {
        TabBar(
            tabs: model.tabs,
            activeID: model.activeTab?.id,
            label: { TabBarLabel(icon: Ph.sparkle.regular, title: model.title(of: $0), isPinned: $0.isPinned) },
            select: { model.select($0) },
            close: { model.close($0) },
            move: { model.move($0, to: $1) },
            togglePin: { model.togglePin($0) },
            rename: { model.rename($0, to: $1) },
            openTab: startAnother
        ) {
            AgentStartMenu(catalog: model.catalog, start: { agent in Task { await model.startSession(agent) } }) {
                HoverIconLabel(icon: Ph.plus.regular)
            }
            .disabled(model.workspace == nil)
        }
    }

    /// Another session, with the agent used last.
    private func startAnother() {
        guard model.workspace != nil else { return }
        Task { await model.startSession() }
    }
}
