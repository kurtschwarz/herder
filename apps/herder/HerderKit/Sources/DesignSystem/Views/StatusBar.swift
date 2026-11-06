import SwiftUI

/// The strip under the centre column. It owns the hairline, the type and the
/// padding; what goes in it is each feature's to say, through two slots, so no
/// feature has to import another to put an item here.
public struct StatusBar<Leading: View, Trailing: View>: View {
    private let leading: Leading
    private let trailing: Trailing

    public init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.Palette.hairline).frame(height: 1)

            HStack(spacing: Theme.Spacing.loose) {
                leading
                Spacer(minLength: 0)
                trailing
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.Palette.secondaryText)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, Theme.Spacing.paneInset)
            .padding(.vertical, Theme.Spacing.tight)
        }
    }
}
