import SwiftUI

/// A Phosphor icon drawn as a template, so `foregroundStyle` colours it like
/// any SF Symbol.
///
/// ``Ph``'s icons are plain resizable images, and `foregroundStyle` does
/// nothing to an image that keeps its own colours. Rendering as a template is
/// what makes them take the style, and what lets a button recolour one on
/// hover.
public struct PhIcon: View {
    private let image: Image
    private let size: CGFloat

    public init(_ image: Image, size: CGFloat) {
        self.image = image
        self.size = size
    }

    public var body: some View {
        image
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}
