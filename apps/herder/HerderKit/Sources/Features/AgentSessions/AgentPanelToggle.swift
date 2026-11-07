import DesignSystem
import PhosphorSwift
import SwiftUI

/// The status bar's button for the panel: lit while it is open.
public struct AgentPanelToggle: View {
    private let model: AgentPanelModel

    public init(model: AgentPanelModel) {
        self.model = model
    }

    public var body: some View {
        Button {
            Task { await model.toggle() }
        } label: {
            HStack(spacing: Theme.Spacing.tight + 2) {
                PhIcon(Ph.sparkle.regular, size: 14)
                Text("Agents")
            }
            .foregroundStyle(model.isOpen ? Theme.Palette.violet : Theme.Palette.secondaryText)
        }
        .buttonStyle(.plain)
        .disabled(model.workspace == nil)
        .help(model.isOpen ? "Hide Agents" : "Show Agents")
    }
}
