import SwiftUI

/// The gap above a panel under the editor, as something to grab: the
/// horizontal counterpart of ``ResizeHandle``, for the height of the panel
/// below it.
///
/// Reports the height the drag proposes and leaves holding it to a limit to
/// whoever owns the layout. Put it in the layout in place of the gap.
public struct PanelResizeHandle: View {
    let height: CGFloat
    let onResize: (CGFloat) -> Void
    let onCommit: () -> Void
    let onReset: () -> Void

    /// The panel's height when the drag began; see ``ResizeHandle``.
    @State private var startHeight: CGFloat?
    @State private var isHovering = false

    public init(
        height: CGFloat,
        onResize: @escaping (CGFloat) -> Void,
        onCommit: @escaping () -> Void,
        onReset: @escaping () -> Void
    ) {
        self.height = height
        self.onResize = onResize
        self.onCommit = onCommit
        self.onReset = onReset
    }

    public var body: some View {
        Capsule()
            .fill(Theme.Palette.grip)
            .opacity(isActive ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: isActive)
            .frame(width: Theme.Size.gripLength, height: Theme.Size.gripThickness)
            .frame(height: Theme.Spacing.paneGap)
            .frame(maxWidth: .infinity)
            .overlay {
                ResizeHandleSurface(
                    axis: .vertical,
                    onDrag: { distance in
                        let start = startHeight ?? height
                        startHeight = start
                        onResize(start + distance)
                    },
                    onDragEnded: {
                        startHeight = nil
                        onCommit()
                    },
                    onDoubleClick: onReset,
                    onHover: { isHovering = $0 }
                )
            }
            .accessibilityHidden(true)
    }

    private var isActive: Bool {
        isHovering || startHeight != nil
    }
}
