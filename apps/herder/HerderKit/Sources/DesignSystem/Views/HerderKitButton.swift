import SwiftUI

extension HerderKit {
    /// The app's button, in one of its variants. Always shows a hand over it,
    /// even while disabled: a button that cannot be pressed yet is still a
    /// button.
    public struct Button<Label: View>: View {
        public enum Variant {
            /// The filled, violet call to action.
            case primary
            /// The quiet button beside a primary one.
            case secondary
            /// A glyph on its own, with a plate that appears on hover.
            case icon(size: CGFloat)

            /// The icon plate at its standard size.
            public static var icon: Self { .icon(size: Theme.Size.iconButton) }
        }

        private let variant: Variant
        private let action: () -> Void
        private let label: Label

        public init(_ variant: Variant, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
            self.variant = variant
            self.action = action
            self.label = label()
        }

        public var body: some View {
            Group {
                switch variant {
                case .primary:
                    SwiftUI.Button(action: action) { label }.buttonStyle(.primary)
                case .secondary:
                    SwiftUI.Button(action: action) { label }.buttonStyle(.secondary)
                case .icon(let size):
                    SwiftUI.Button(action: action) { label }.buttonStyle(.icon(size: size))
                }
            }
            .pointerStyle(.link)
        }
    }
}

extension HerderKit.Button where Label == Text {
    public init(_ title: String, _ variant: Variant = .secondary, action: @escaping () -> Void) {
        self.init(variant, action: action) { Text(title) }
    }
}

extension HerderKit.Button where Label == PhIcon {
    /// An icon button for `icon`.
    public init(icon: Image, iconSize: CGFloat = 14, size: CGFloat = Theme.Size.iconButton, action: @escaping () -> Void) {
        self.init(.icon(size: size), action: action) { PhIcon(icon, size: iconSize) }
    }
}

#if DEBUG
#Preview {
    HStack(spacing: Theme.Spacing.normal) {
        HerderKit.Button("Cancel") {}
        HerderKit.Button("Start", .primary) {}
        HerderKit.Button("Start", .primary) {}.disabled(true)
        HerderKit.Button(icon: Ph.arrowClockwise) {}
    }
    .padding(Theme.Spacing.section)
    .background(Theme.Palette.modal)
}
#endif
