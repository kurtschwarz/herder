import SwiftUI

/// The mark beside a choice that can be ticked with others. Only the mark:
/// the row it sits in takes the click.
public struct CheckBox: View {
    private let isOn: Bool

    public init(isOn: Bool) {
        self.isOn = isOn
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        ZStack {
            if isOn {
                shape.fill(Theme.Palette.violet)
                PhIcon(Ph.checkBold, size: 11)
                    .foregroundStyle(Theme.Palette.onViolet)
            } else {
                shape.strokeBorder(Theme.Palette.tertiaryText, lineWidth: 1.5)
            }
        }
        .frame(width: 18, height: 18)
    }
}

#if DEBUG
#Preview {
    HStack(spacing: Theme.Spacing.loose) {
        CheckBox(isOn: false)
        CheckBox(isOn: true)
    }
    .padding()
    .background(Theme.Palette.modal)
}
#endif
