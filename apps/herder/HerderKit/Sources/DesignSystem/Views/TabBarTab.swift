import AppKit
import PhosphorSwift
import SwiftUI

/// One tab of a ``TabBar``: a click shows it, a double-click or its menu
/// names it in place where it can be named, and its button closes it.
struct TabBarTab<Menu: View>: View {
    let label: TabBarLabel
    let isActive: Bool
    /// Picked up and being dragged along the strip.
    let isLifted: Bool
    let select: () -> Void
    /// `nil` for a tab that cannot be named, as a file's cannot.
    let rename: ((String) -> Void)?
    let togglePin: () -> Void
    let close: () -> Void
    let menu: Menu

    @State private var isHovering = false
    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isFieldFocused: Bool
    @State private var outsideClick = ClickMonitor()
    @State private var isFlashing = false

    var body: some View {
        Group {
            if isEditing {
                chrome { field }
            } else {
                // A `Button`, not a tap gesture. A gesture inside a horizontal
                // `ScrollView` has to win against the scroll view's own
                // recogniser, and intermittently does not — which is a tab you
                // have to click three times. A button is routed through
                // AppKit's control path and does not negotiate for the click.
                Button(action: click) {
                    chrome { title }
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .trailing) {
            // Gone from the tab in hand, so a drag that ends on it cannot be
            // taken for a close.
            trailingMark
                .padding(.trailing, Theme.Spacing.normal)
                .opacity(isLifted ? 0 : 1)
                .allowsHitTesting(!isLifted)
        }
        // Its double-click is its own, not the window's zoom.
        .background(DoubleClickClaim())
        .onHover { isHovering = $0 }
        .help(label.help ?? "")
        .contextMenu {
            if rename != nil {
                Button("Rename\u{2026}", action: beginEditing)
            }
            Button(label.isPinned ? "Unpin Tab" : "Pin Tab", action: togglePin)
            menu
            Divider()
            Button("Close Tab", action: close)
        }
        .onDisappear { outsideClick.stop() }
        .onChange(of: label.attention) {
            guard !isActive else { return }
            withAnimation(.easeOut(duration: 0.1)) { isFlashing = true }
            withAnimation(.easeOut(duration: 0.6).delay(0.15)) { isFlashing = false }
        }
    }

    /// The surface every state of the tab sits on, around `content`.
    private func chrome(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: Theme.Spacing.normal) {
            PhIcon(label.isPinned ? Ph.pushPin.fill : label.icon, size: 14)
                .foregroundStyle(iconColor)

            content()

            // Where the close button goes. It is laid over rather than in, so
            // that a click landing beside the ✕ shows the tab instead of
            // falling into a gap between two controls.
            if hasTrailingMark {
                Color.clear.frame(width: Theme.Size.chevron, height: Theme.Size.chevron)
            }
        }
        .padding(.horizontal, Theme.Spacing.normal)
        .frame(height: Theme.Size.iconButton)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(fill)
                .shadow(
                    color: isLifted ? Theme.Shadow.liftColor : .clear,
                    radius: Theme.Shadow.liftRadius,
                    y: Theme.Shadow.liftOffset
                )
        }
        // The whole tab, not just where there happens to be a glyph.
        .contentShape(.rect)
    }

    private var title: some View {
        HStack(spacing: Theme.Spacing.tight) {
            // One weight for every tab: the colour says which is showing, and
            // a weight that changed would resize the tab under the pointer as
            // it was clicked.
            Text(label.title)
                .font(.system(size: 13))
                .foregroundStyle(isActive ? Theme.Palette.text : Theme.Palette.secondaryText)
                .strikethrough(label.isGone)

            if let detail = label.detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.tertiaryText)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: 200, alignment: .leading)
        .opacity(label.isGone ? Theme.Opacity.ignored : 1)
    }

    private var field: some View {
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
    }

    /// A pinned tab has no close button: that is what pinning is for. It
    /// still shows that it has unsaved changes.
    private var hasTrailingMark: Bool { !label.isPinned || label.isDirty }

    @ViewBuilder
    private var trailingMark: some View {
        if label.isDirty && (label.isPinned || !isHovering) {
            Circle()
                .fill(Theme.Palette.secondaryText)
                .frame(width: Theme.Size.unsavedDot, height: Theme.Size.unsavedDot)
                .frame(width: Theme.Size.chevron, height: Theme.Size.chevron)
                .help("Unsaved Changes")
        } else if !label.isPinned {
            TabBarCloseButton(action: close)
        }
    }

    private var iconColor: Color {
        if let color = label.iconColor { return color }
        return isActive ? Theme.Palette.accent : Theme.Palette.tertiaryText
    }

    /// The tab showing sits on a surface; the rest are flat on the window.
    private var fill: Color {
        if isFlashing { return Theme.Palette.controlPressed }
        if isActive || isLifted { return Theme.Palette.control }
        return isHovering ? Theme.Palette.glassTint : .clear
    }

    /// The button's click: the second of a double-click names the tab, where
    /// it can be named. The first has already shown it.
    private func click() {
        if rename != nil, NSApp.currentEvent?.clickCount == 2 {
            beginEditing()
        } else {
            select()
        }
    }

    private func beginEditing() {
        draft = label.title
        isEditing = true
        outsideClick.start { finishEditing(keep: true) }
        // The field is made by this change, so it can take focus only after.
        Task { isFieldFocused = true }
    }

    private func finishEditing(keep: Bool) {
        guard isEditing else { return }
        isEditing = false
        outsideClick.stop()
        if keep { rename?(draft) } else { select() }
    }
}
