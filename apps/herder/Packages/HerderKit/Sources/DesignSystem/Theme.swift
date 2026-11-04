import SwiftUI

/// Design tokens, taken from the Tokyo Night main-window mockup.
///
/// Features reference these instead of hard-coding values, so a change here moves
/// the whole app at once.
public enum Theme {
    public enum Spacing {
        public static let tight: CGFloat = 4
        public static let normal: CGFloat = 8
        public static let loose: CGFloat = 16
        public static let section: CGFloat = 24

        /// Inset between the window edge and the panes floating inside it.
        public static let windowPadding: CGFloat = 10
        /// Gap between adjacent panes.
        public static let paneGap: CGFloat = 10
        /// Horizontal inset for content inside a pane.
        public static let paneInset: CGFloat = 16
    }

    public enum Size {
        public static let sidebarWidth: CGFloat = 236
        /// Header strip tall enough to clear the traffic lights.
        public static let titleBar: CGFloat = 48
        public static let wolfMark = CGSize(width: 20, height: 26)
    }

    public enum Radius {
        /// Matches the window's own corner so the two read as one shape.
        ///
        /// AppKit does not expose the window corner radius, so this was measured
        /// off a screenshot: the arc completes 30px from the window's top edge at
        /// 2x. It is a macOS 26 value; earlier systems round their windows less.
        public static let pane: CGFloat = 16
    }

    public enum Palette {
        /// The window itself. Panes sit on top of this.
        public static let window = Color(red: 28 / 255, green: 28 / 255, blue: 31 / 255, opacity: 0.97)

        /// Dark wash over the blurred desktop. Light enough that the wallpaper's
        /// colour still reads through.
        public static let windowTint = Color(red: 28 / 255, green: 28 / 255, blue: 31 / 255, opacity: 0.55)

        public static let paneTop = Color(red: 27 / 255, green: 27 / 255, blue: 30 / 255, opacity: 0.94)
        public static let paneBottom = Color(red: 23 / 255, green: 24 / 255, blue: 28 / 255, opacity: 0.94)

        /// Faint violet cast over panes, the mockup's stand-in for glass.
        public static let glassTint = Color(red: 160 / 255, green: 130 / 255, blue: 255 / 255, opacity: 0.03)

        /// Top-edge highlight that reads as a light source above the window.
        public static let paneHighlight = Color.white.opacity(0.04)

        public static let text = Color(red: 229 / 255, green: 229 / 255, blue: 234 / 255)
        public static let secondaryText = Color(red: 152 / 255, green: 152 / 255, blue: 159 / 255)
        public static let tertiaryText = Color(red: 128 / 255, green: 128 / 255, blue: 136 / 255)
        public static let accent = Color(red: 122 / 255, green: 162 / 255, blue: 247 / 255)
    }

    public enum Gradient {
        /// Vertical fill for a pane.
        public static let pane = LinearGradient(
            colors: [Palette.paneTop, Palette.paneBottom],
            startPoint: .top,
            endPoint: .bottom
        )

        /// Sunset ramp for the wolf mark, matching the app icon.
        public static let wolf = LinearGradient(
            stops: [
                .init(color: Color(red: 184 / 255, green: 123 / 255, blue: 255 / 255), location: 0),
                .init(color: Color(red: 255 / 255, green: 95 / 255, blue: 180 / 255), location: 0.45),
                .init(color: Color(red: 255 / 255, green: 158 / 255, blue: 122 / 255), location: 0.72),
                .init(color: Color(red: 255 / 255, green: 212 / 255, blue: 92 / 255), location: 1),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public enum Shadow {
        public static let paneColor = Color.black.opacity(0.35)
        /// Half the mockup's 30px CSS blur: SwiftUI radius is roughly blur / 2.
        public static let paneRadius: CGFloat = 15
        public static let paneOffset: CGFloat = 10
    }
}
