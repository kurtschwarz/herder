import Core
import DesignSystem
import SwiftUI
import TerminalUI

/// The terminal under the editor: a header with the tabs, and the screen of the
/// one showing.
public struct TerminalPanel: View {
    private let model: TerminalModel

    public init(model: TerminalModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            TerminalHeader(model: model)
            Rectangle().fill(Theme.Palette.hairline).frame(height: 1)

            if let tab = model.activeTab {
                TerminalView(screen: tab.screen, focusRequest: model.focusRequest)
                    .id(tab.id)
            } else {
                Color.clear
            }
        }
        .paneBackgroundSquareTop()
        .alert(
            "Couldn\u{2019}t start a terminal",
            isPresented: Binding(
                get: { model.spawnFailure != nil },
                set: { if !$0 { model.dismissSpawnFailure() } }
            ),
            presenting: model.spawnFailure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { reason in
            Text(reason)
        }
    }
}
