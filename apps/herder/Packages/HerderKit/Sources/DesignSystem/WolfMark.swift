import SwiftUI

/// The app's wordless mark: the icon's wolf silhouette filled with the sunset ramp.
public struct WolfMark: View {
    private let size: CGSize

    public init(size: CGSize = Theme.Size.wolfMark) {
        self.size = size
    }

    public var body: some View {
        WolfShape()
            .fill(Theme.Gradient.wolf, style: FillStyle(eoFill: true))
            .frame(width: size.width, height: size.height)
            .accessibilityLabel("Herder")
    }
}

#if DEBUG
#Preview {
    HStack(spacing: Theme.Spacing.section) {
        WolfMark()
        WolfMark(size: CGSize(width: 80, height: 104))
    }
    .padding(Theme.Spacing.section)
    .background(Theme.Palette.window)
}
#endif
