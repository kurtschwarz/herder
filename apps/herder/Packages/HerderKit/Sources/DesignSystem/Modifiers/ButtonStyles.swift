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
            .opacity(isEnabled ? 1 : 0.4)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    public static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
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
