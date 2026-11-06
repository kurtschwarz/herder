import SwiftUI

/// The rounded, slightly-lifted surface that panes sit on.
///
/// A pane is a gradient fill, a violet glass cast, a one-point highlight along the
/// top edge, and a drop shadow. Applying it as a modifier keeps every pane in the
/// app identical without a shared superview.
public struct PaneBackground: ViewModifier {
    /// A fixed radius rather than `ConcentricRectangle`: concentric means the
    /// window's radius *minus* the inset, which reads tighter than the window's
    /// corner. `Theme.Radius.pane` matches the window outright.
    private let shape = RoundedRectangle(cornerRadius: Theme.Radius.pane, style: .continuous)

    public init() {}

    public func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(Theme.Gradient.pane)
                    .overlay { shape.fill(Theme.Palette.glassTint) }
                    .overlay {
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [Theme.Palette.paneHighlight, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    }
                    .shadow(
                        color: Theme.Shadow.paneColor,
                        radius: Theme.Shadow.paneRadius,
                        y: Theme.Shadow.paneOffset
                    )
            }
            .clipShape(shape)
    }
}

extension View {
    /// Draws this view as a floating pane.
    public func paneBackground() -> some View {
        modifier(PaneBackground())
    }

    /// Draws this view as a floating pane made of Liquid Glass, the same material
    /// as the window backdrop, instead of the solid pane fill.
    public func glassPaneBackground() -> some View {
        glassEffect(
            .regular.tint(Theme.Palette.windowTint),
            in: RoundedRectangle(cornerRadius: Theme.Radius.pane, style: .continuous)
        )
    }
}

#if DEBUG
#Preview {
    HStack(spacing: Theme.Spacing.paneGap) {
        Color.clear
            .frame(width: Theme.Size.sidebarWidth)
            .paneBackground()
        Color.clear
    }
    .padding(Theme.Spacing.windowPadding)
    .frame(width: 620, height: 360)
    .background(Theme.Palette.window)
}
#endif
