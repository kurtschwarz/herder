import DesignSystem
import PhosphorSwift
import SwiftUI

/// The strip over the screen: a tab for each shell, a button for another, and
/// on the right where the shell is and a button to hide the panel.
struct TerminalHeader: View {
    let model: TerminalModel

    var body: some View {
        HStack(spacing: Theme.Spacing.tight) {
            ForEach(model.tabs) { tab in
                TerminalTabView(
                    tab: tab,
                    isActive: tab.id == model.activeTab?.id,
                    select: { model.select(tab) },
                    close: { model.close(tab) }
                )
            }

            Button {
                Task { await model.openTab() }
            } label: {
                PhIcon(Ph.plus.regular, size: 14)
                    .frame(width: Theme.Size.iconButton, height: Theme.Size.iconButton)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Palette.secondaryText)
            .help("New Terminal Tab")

            Spacer(minLength: Theme.Spacing.loose)

            if let directory = model.activeTab?.directory {
                Text(model.label(for: directory))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Button {
                model.hide()
            } label: {
                PhIcon(Ph.x.regular, size: 14)
                    .frame(width: Theme.Size.iconButton, height: Theme.Size.iconButton)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Palette.secondaryText)
            .help("Hide Terminal")
        }
        .padding(.horizontal, Theme.Spacing.normal)
        .padding(.vertical, Theme.Spacing.tight)
    }
}

private struct TerminalTabView: View {
    let tab: TerminalTab
    let isActive: Bool
    let select: () -> Void
    let close: () -> Void

    @State private var isHovering = false
    @State private var isFlashing = false

    var body: some View {
        HStack(spacing: Theme.Spacing.normal) {
            PhIcon(Ph.terminal.regular, size: 14)
                .foregroundStyle(isActive ? Theme.Palette.accent : Theme.Palette.tertiaryText)

            Text(tab.title)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Theme.Palette.text : Theme.Palette.secondaryText)
                .lineLimit(1)

            Button(action: close) {
                PhIcon(Ph.x.bold, size: 10)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Palette.tertiaryText)
            .opacity(isActive || isHovering ? 1 : 0)
            .help("Close Terminal")
        }
        .padding(.horizontal, Theme.Spacing.normal + 2)
        .frame(height: Theme.Size.iconButton)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .fill(isFlashing ? Theme.Palette.controlPressed : isActive ? Theme.Palette.control : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
        // A bell is a silent flash of the tab, and only of one not in front:
        // the one in front is being looked at.
        .onChange(of: tab.screen.bellCount) {
            guard !isActive else { return }
            withAnimation(.easeOut(duration: 0.1)) { isFlashing = true }
            withAnimation(.easeOut(duration: 0.6).delay(0.15)) { isFlashing = false }
        }
    }
}
