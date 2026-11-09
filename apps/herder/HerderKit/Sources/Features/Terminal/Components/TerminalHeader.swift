import DesignSystem
import PhosphorSwift
import SwiftUI

/// The strip over the screen: a tab for each shell, a button for another, and
/// on the right where the shell is and a button to hide the panel.
struct TerminalHeader: View {
    let model: TerminalModel

    var body: some View {
        TabBar(
            tabs: model.tabs,
            activeID: model.activeTab?.id,
            label: { tab in
                TabBarLabel(
                    icon: Ph.terminal.regular,
                    title: tab.displayTitle,
                    isPinned: tab.isPinned,
                    attention: tab.screen.bellCount
                )
            },
            select: { model.select($0) },
            close: { tab in Task { await model.requestClose(tab) } },
            move: { model.move($0, to: $1) },
            togglePin: { model.togglePin($0) },
            rename: { model.rename($0, to: $1) },
            openTab: { Task { await model.openTab() } }
        ) { _ in
            EmptyView()
        } newTab: {
            HoverIconButton(icon: Ph.plus.regular, help: "New Terminal Tab") {
                Task { await model.openTab() }
            }
        } trailing: {
            if let directory = model.activeTab?.directory {
                Text(model.label(for: directory))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            HoverIconButton(icon: Ph.caretDown.regular, help: "Hide Terminal") {
                model.hide()
            }
        }
    }
}
