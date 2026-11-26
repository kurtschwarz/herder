import SwiftUI

/// The filled, violet call to action. One per modal.
public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.Palette.onViolet)
            .padding(.horizontal, Theme.Spacing.loose + Theme.Spacing.tight)
            .frame(minHeight: Theme.Size.control)
            .background(
                Theme.Palette.violet.opacity(configuration.isPressed ? 0.8 : 1),
                in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            )
            .pointerStyle(isEnabled ? .link : nil)
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// The quiet button beside a primary one, and for secondary actions like Browse.
public struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        configuration.label
            .font(.body)
            .foregroundStyle(Theme.Palette.text)
            .padding(.horizontal, Theme.Spacing.loose)
            .frame(minHeight: Theme.Size.control)
            .background(
                configuration.isPressed ? Theme.Palette.controlPressed : Theme.Palette.control,
                in: shape
            )
            .overlay { shape.strokeBorder(Theme.Palette.hairline, lineWidth: 1) }
            .pointerStyle(isEnabled ? .link : nil)
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// A glyph on its own, with a rounded plate that appears on hover and press.
///
/// The whole square responds, not just the strokes of the glyph.
public struct IconButtonStyle: ButtonStyle {
    private let size: CGFloat

    public init(size: CGFloat = Theme.Size.iconButton) {
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        Plate(configuration: configuration, size: size)
    }

    private struct Plate: View {
        let configuration: ButtonStyleConfiguration
        let size: CGFloat

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(isHovering || configuration.isPressed ? Theme.Palette.text : Theme.Palette.secondaryText)
                .frame(width: size, height: size)
                .background(
                    configuration.isPressed ? Theme.Palette.controlPressed : (isHovering ? Theme.Palette.control : .clear),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                )
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
                .pointerStyle(isEnabled ? .link : nil)
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    public static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == IconButtonStyle {
    public static var icon: IconButtonStyle { IconButtonStyle() }

    /// For a row too short for the standard plate.
    public static func icon(size: CGFloat) -> IconButtonStyle { IconButtonStyle(size: size) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    public static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

#if DEBUG
#Preview {
    HStack(spacing: Theme.Spacing.normal) {
        Button("Cancel") {}.buttonStyle(.secondary)
        Button("Add workspace") {}.buttonStyle(.primary)
        Button("Add workspace") {}.buttonStyle(.primary).disabled(true)
    }
    .padding(Theme.Spacing.section)
    .background(Theme.Palette.modal)
}
#endif
