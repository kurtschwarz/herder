import SwiftUI

/// The gap between two panes, as something to grab: a short pill, centred, that
/// drags the width of the pane beside it. The pill shows only while the pointer
/// is over the gap or the drag is under way; the cursor is the only sign before
/// that.
///
/// It only turns a gesture into a number. It reports the width the drag
/// proposes and leaves holding it to a limit to whoever owns the layout. Put it
/// in the layout in place of the gap, so it is as wide as the gap.
public struct ResizeHandle: View {
    /// Which way widens the pane: `.trailing` for a pane on the leading side of
    /// the handle, `.leading` for one on its trailing side.
    let widens: HorizontalEdge
    let width: CGFloat
    let onResize: (CGFloat) -> Void
    let onCommit: () -> Void
    let onReset: () -> Void

    /// The pane's width when the drag began. Everything is measured from it, so
    /// the proposal does not depend on where the handle is, which moves as the
    /// pane does.
    @State private var startWidth: CGFloat?
    @State private var isHovering = false

    public init(
        widens: HorizontalEdge,
        width: CGFloat,
        onResize: @escaping (CGFloat) -> Void,
        onCommit: @escaping () -> Void,
        onReset: @escaping () -> Void
    ) {
        self.widens = widens
        self.width = width
        self.onResize = onResize
        self.onCommit = onCommit
        self.onReset = onReset
    }

    public var body: some View {
        Capsule()
            .fill(Theme.Palette.grip)
            .opacity(isActive ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: isActive)
            .frame(width: Theme.Size.gripThickness, height: Theme.Size.gripLength)
            .frame(width: Theme.Spacing.paneGap)
            .frame(maxHeight: .infinity)
            .overlay {
                ResizeHandleSurface(
                    onDrag: { distance in
                        let start = startWidth ?? width
                        startWidth = start
                        let direction: CGFloat = widens == .trailing ? 1 : -1
                        onResize(start + direction * distance)
                    },
                    onDragEnded: {
                        startWidth = nil
                        onCommit()
                    },
                    onDoubleClick: onReset,
                    onHover: { isHovering = $0 }
                )
            }
            .accessibilityHidden(true)
    }

    private var isActive: Bool {
        isHovering || startWidth != nil
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 0) {
        Color.clear.frame(width: 160).paneBackground()
        ResizeHandle(widens: .trailing, width: 160, onResize: { _ in }, onCommit: {}, onReset: {})
        Color.clear.paneBackground()
    }
    .padding(Theme.Spacing.windowPadding)
    .frame(width: 400, height: 240)
    .background(Theme.Palette.window)
}
#endif
