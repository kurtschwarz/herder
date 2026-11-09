import DesignSystem
import SwiftUI

/// The status bar's button for the panel: lit while it is open.
public struct TerminalToggle: View {
    private let model: TerminalModel

    public init(model: TerminalModel) {
        self.model = model
    }

    public var body: some View {
        Button {
            Task { await model.toggle() }
        } label: {
            HStack(spacing: Theme.Spacing.tight + 2) {
                PhIcon(Ph.terminal, size: 14)
                Text("Terminal")
            }
            .foregroundStyle(model.isOpen ? Theme.Palette.violet : Theme.Palette.secondaryText)
        }
        .buttonStyle(.plain)
        .disabled(model.workspace == nil)
        .help(model.isOpen ? "Hide Terminal" : "Show Terminal")
    }
}
