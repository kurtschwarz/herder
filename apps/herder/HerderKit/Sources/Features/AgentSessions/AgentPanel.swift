import Core
import DesignSystem
import SwiftUI
import TerminalUI

/// The agent panel: a header with the open sessions' tabs, and the terminal UI
/// of the one showing. Fills the pane it is put in, and draws no surface of its
/// own: the window gives it one.
public struct AgentPanel: View {
    private let model: AgentPanelModel

    public init(model: AgentPanelModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            AgentHeader(model: model)

            Group {
                if let tab = model.activeTab {
                    AgentTabContent(tab: tab, model: model)
                } else {
                    AgentEmptyState(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// What a tab shows for whichever state its terminal UI is in.
private struct AgentTabContent: View {
    let tab: AgentTab
    let model: AgentPanelModel

    var body: some View {
        switch tab.phase {
        case .starting:
            ProgressView()
                .controlSize(.small)
        case .running:
            if let screen = tab.screen {
                TerminalView(screen: screen, focusRequest: model.focusRequest)
                    .id(tab.generation)
            }
        case .exited(let code):
            VStack(spacing: 0) {
                if let screen = tab.screen {
                    TerminalView(screen: screen, focusRequest: model.focusRequest)
                        .id(tab.generation)
                }
                Banner(
                    message: code == 127
                        ? "\u{201C}\(tab.agent.program)\u{201D} isn\u{2019}t installed, or isn\u{2019}t on your PATH."
                        : "\(tab.agent.displayName) exited with code \(code).",
                    action: "Reattach"
                ) { Task { await model.reattach(tab) } }
            }
        case .failed(let reason):
            Banner(message: reason, action: "Try Again") { Task { await model.reattach(tab) } }
        }
    }
}

/// A line saying what went wrong, with the one thing to do about it.
private struct Banner: View {
    let message: String
    let action: String
    let perform: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.normal) {
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.Palette.secondaryText)
                .multilineTextAlignment(.center)
            Button(action, action: perform)
                .buttonStyle(.secondary)
        }
        .padding(Theme.Spacing.loose)
        .frame(maxWidth: .infinity)
    }
}

/// What the panel shows with no session open: a button for each agent.
private struct AgentEmptyState: View {
    let model: AgentPanelModel

    var body: some View {
        VStack(spacing: Theme.Spacing.normal) {
            Text("Start a session")
                .font(.callout)
                .foregroundStyle(Theme.Palette.secondaryText)
            ForEach(model.catalog.agents.filter(\.isRunnable)) { agent in
                Button(agent.displayName) { Task { await model.startSession(agent) } }
                    .buttonStyle(.secondary)
            }
        }
        .disabled(model.workspace == nil)
        .padding(Theme.Spacing.loose)
    }
}
