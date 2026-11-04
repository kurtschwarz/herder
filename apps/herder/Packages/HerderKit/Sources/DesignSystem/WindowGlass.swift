import SwiftUI

/// The window's backdrop: a Liquid Glass sheet over the desktop, tinted dark so
/// the panes stay legible while the wallpaper's colour still reads through.
///
/// The window must be non-opaque for the glass to see the desktop (see
/// `WindowChrome`).
public struct WindowGlass: View {
    public init() {}

    public var body: some View {
        Color.clear
            .glassEffect(.regular.tint(Theme.Palette.windowTint), in: .rect)
    }
}

#if DEBUG
#Preview {
    WindowGlass()
        .frame(width: 400, height: 260)
}
#endif
