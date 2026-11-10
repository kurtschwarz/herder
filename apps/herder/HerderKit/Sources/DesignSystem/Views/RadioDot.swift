import SwiftUI

/// The mark beside one of several choices, filled when it is the one picked.
/// Only the mark: the row it sits in takes the click.
public struct RadioDot: View {
    private let isSelected: Bool

    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    public var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? .clear : Theme.Palette.tertiaryText, lineWidth: 1.25)
            if isSelected {
                Circle().fill(Theme.Palette.violet)
                Circle().fill(Theme.Palette.onViolet).frame(width: 6, height: 6)
            }
        }
        .frame(width: 15, height: 15)
    }
}

#if DEBUG
#Preview {
    HStack(spacing: Theme.Spacing.loose) {
        RadioDot(isSelected: false)
        RadioDot(isSelected: true)
    }
    .padding()
    .background(Theme.Palette.modal)
}
#endif
