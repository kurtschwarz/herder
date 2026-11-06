import Core
import DesignSystem
import SwiftUI
import TerminalUI

/// The terminal under the editor: a header with the tabs, and the screen of the
/// one showing. Has no surface of its own: like the editor above it, it sits
/// straight on the window.
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
        .alert(
            model.closePrompt.map { "Do you want to close \u{201C}\(TerminalTitle.truncated($0.command, to: 40))\u{201D}?" } ?? "",
            isPresented: Binding(
                get: { model.closePrompt != nil },
                set: { if !$0 { model.answerClose(confirm: false) } }
            ),
            presenting: model.closePrompt
        ) { _ in
            Button("Close", role: .destructive) { model.answerClose(confirm: true) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It is still running, and closing the terminal will end it.")
        }
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
