import SwiftUI

/// A glyph-only button that lights a plate behind it under the pointer, which
/// becomes a hand.
///
/// For the strips over a panel, where the button sits on the pane itself and
/// the plate is the only sign it is one.
public struct HoverIconButton: View {
    private let icon: Image
    private let iconSize: CGFloat
    private let side: CGFloat
    private let radius: CGFloat
    private let help: String
    private let action: () -> Void

    @State private var isHovering = false

    public init(
        icon: Image,
        iconSize: CGFloat = 14,
        side: CGFloat = Theme.Size.iconButton,
        radius: CGFloat = Theme.Radius.control,
        help: String,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.iconSize = iconSize
        self.side = side
        self.radius = radius
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            PhIcon(icon, size: iconSize)
                .frame(width: side, height: side)
                .background(
                    RoundedRectangle(cornerRadius: radius)
                        .fill(isHovering ? Theme.Palette.control : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: radius))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovering ? Theme.Palette.text : Theme.Palette.secondaryText)
        .onHover { isHovering = $0 }
        .pointerStyle(.link)
        .help(help)
    }
}

/// What ``HoverIconButton`` draws, for a control that is not a plain button,
/// such as a menu. Lights its plate under the pointer the same way.
public struct HoverIconLabel: View {
    private let icon: Image
    private let iconSize: CGFloat
    private let side: CGFloat
    private let radius: CGFloat

    @State private var isHovering = false

    public init(
        icon: Image,
        iconSize: CGFloat = 14,
        side: CGFloat = Theme.Size.iconButton,
        radius: CGFloat = Theme.Radius.control
    ) {
        self.icon = icon
        self.iconSize = iconSize
        self.side = side
        self.radius = radius
    }

    public var body: some View {
        PhIcon(icon, size: iconSize)
            .frame(width: side, height: side)
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(isHovering ? Theme.Palette.control : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .foregroundStyle(isHovering ? Theme.Palette.text : Theme.Palette.secondaryText)
            .onHover { isHovering = $0 }
            .pointerStyle(.link)
    }
}
