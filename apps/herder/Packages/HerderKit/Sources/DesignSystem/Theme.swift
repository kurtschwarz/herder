import SwiftUI

/// Design tokens. Features reference these instead of hard-coding values, so a
/// change here moves the whole app at once.
public enum Theme {
    public enum Spacing {
        public static let tight: CGFloat = 4
        public static let normal: CGFloat = 8
        public static let loose: CGFloat = 16
        public static let section: CGFloat = 24
    }

    public enum Radius {
        public static let card: CGFloat = 10
    }

    public enum Palette {
        public static let accent = Color.accentColor
        public static let surface = Color(nsColor: .controlBackgroundColor)
        public static let separator = Color(nsColor: .separatorColor)
    }
}
