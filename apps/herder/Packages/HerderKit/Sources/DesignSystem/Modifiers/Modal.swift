import SwiftUI

/// The centred card a modal sits on: a flat fill, a hairline, and a large soft
/// shadow. Flatter than a pane on purpose; the shadow does the separating.
public struct ModalSurface: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: Theme.Radius.modal, style: .continuous)

    public init() {}

    public func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(Theme.Palette.modal)
                    .overlay { shape.strokeBorder(Theme.Palette.hairline, lineWidth: 1) }
                    .shadow(
                        color: Theme.Shadow.modalColor,
                        radius: Theme.Shadow.modalRadius,
                        y: Theme.Shadow.modalOffset
                    )
            }
    }
}

/// The boxed group of labelled fields inside a modal.
public struct FieldGroupSurface: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: Theme.Radius.fieldGroup, style: .continuous)

    public init() {}

    public func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(Theme.Palette.fieldGroup)
                    .overlay { shape.strokeBorder(Theme.Palette.hairline, lineWidth: 1) }
            }
    }
}

/// The recessed well a text field or path readout sits in.
public struct FieldSurface: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)

    public init() {}

    public func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(Theme.Palette.field)
                    .overlay { shape.strokeBorder(Theme.Palette.hairline, lineWidth: 1) }
            }
    }
}

extension View {
    public func modalSurface() -> some View {
        modifier(ModalSurface())
    }

    public func fieldGroupSurface() -> some View {
        modifier(FieldGroupSurface())
    }

    public func fieldSurface() -> some View {
        modifier(FieldSurface())
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
        Text("Add workspace")
            .font(.title2.bold())
        Text("~/dev/my-project")
            .font(.body.monospaced())
            .padding(.horizontal, Theme.Spacing.normal + Theme.Spacing.tight)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.control, alignment: .leading)
            .fieldSurface()
            .padding(Theme.Spacing.loose)
            .fieldGroupSurface()
    }
    .foregroundStyle(Theme.Palette.text)
    .padding(Theme.Spacing.section)
    .frame(width: Theme.Size.modalWidth)
    .modalSurface()
    .padding(Theme.Spacing.section * 2)
    .background(Theme.Palette.window)
}
#endif
