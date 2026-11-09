import SwiftUI

/// A tab's ✕. Always visible, so there is no tab whose close button has to be
/// hunted for by hovering first.
struct TabBarCloseButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            PhIcon(Ph.xBold, size: 10)
                .foregroundStyle(isHovering ? Theme.Palette.text : Theme.Palette.tertiaryText)
                .frame(width: Theme.Size.chevron, height: Theme.Size.chevron)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(isHovering ? Theme.Palette.controlPressed : .clear)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Close Tab")
    }
}
