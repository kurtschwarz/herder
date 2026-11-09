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
                    rename: { model.rename(tab, to: $0) },
                    togglePin: { model.togglePin(tab) },
                    close: { Task { await model.requestClose(tab) } }
                )
            }

            HoverIconButton(icon: Ph.plus.regular, help: "New Terminal Tab") {
                Task { await model.openTab() }
            }

            // Empty space is a place to double-click for another terminal, as it
            // is in a browser's tab strip. Only this: a tab's own double-click
            // renames it. Not a `Spacer`, which has nothing for a click to
            // land on whatever its content shape says.
            Color.clear
                .frame(minWidth: Theme.Spacing.loose, maxWidth: .infinity)
                .frame(height: Theme.Size.iconButton)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { Task { await model.openTab() } }

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
        .padding(.horizontal, Theme.Spacing.normal)
        .padding(.vertical, Theme.Spacing.tight)
    }
}

private struct TerminalTabView: View {
    let tab: TerminalTab
    let isActive: Bool
    let select: () -> Void
    let rename: (String) -> Void
    let togglePin: () -> Void
    let close: () -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isFieldFocused: Bool
    @State private var outsideClick = ClickMonitor()
    @State private var isHovering = false
    @State private var isFlashing = false

    var body: some View {
        HStack(spacing: Theme.Spacing.normal) {
            PhIcon(tab.isPinned ? Ph.pushPin.fill : Ph.terminal.regular, size: 14)
                .foregroundStyle(isActive ? Theme.Palette.accent : Theme.Palette.tertiaryText)

            if isEditing {
                TextField("Name", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.text)
                    .focused($isFieldFocused)
                    .frame(width: 120)
                    .onSubmit { finishEditing(keep: true) }
                    .onExitCommand { finishEditing(keep: false) }
                    // Clicking away keeps what was typed, as in Finder.
                    .onChange(of: isFieldFocused) { _, focused in
                        if !focused { finishEditing(keep: true) }
                    }
            } else {
                Text(tab.displayTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(isActive ? Theme.Palette.text : Theme.Palette.secondaryText)
                    .lineLimit(1)
            }

            // A pinned tab has none: that is what pinning is for.
            if !tab.isPinned {
                HoverIconButton(icon: Ph.x.bold, iconSize: 10, side: 18, radius: 5, help: "Close Terminal", action: close)
                    .opacity(isActive || isHovering ? 1 : 0)
            }
        }
        .padding(.horizontal, Theme.Spacing.normal + 2)
        .frame(height: Theme.Size.iconButton)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .fill(isFlashing ? Theme.Palette.controlPressed : isActive ? Theme.Palette.control : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
        .onTapGesture(count: 2, perform: beginEditing)
        .onTapGesture(perform: select)
        .contextMenu {
            Button("Rename\u{2026}", action: beginEditing)
            Button(tab.isPinned ? "Unpin Tab" : "Pin Tab", action: togglePin)
            Button("Close", action: close)
        }
        .onHover { isHovering = $0 }
        .onDisappear { outsideClick.stop() }
        // A bell is a silent flash of the tab, and only of one not in front:
        // the one in front is being looked at.
        .onChange(of: tab.screen.bellCount) {
            guard !isActive else { return }
            withAnimation(.easeOut(duration: 0.1)) { isFlashing = true }
            withAnimation(.easeOut(duration: 0.6).delay(0.15)) { isFlashing = false }
        }
    }

    private func beginEditing() {
        draft = tab.displayTitle
        isEditing = true
        // Focus leaves a text field only for something that takes it, and
        // most of the window does not. So a click anywhere but the field ends
        // the edit itself.
        outsideClick.start { finishEditing(keep: true) }
        // The field is made by this change, so it can take focus only after.
        Task { isFieldFocused = true }
    }

    private func finishEditing(keep: Bool) {
        guard isEditing else { return }
        isEditing = false
        outsideClick.stop()
        if keep { rename(draft) } else { select() }
    }
}
