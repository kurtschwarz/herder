import SwiftUI

/// What one tab of a ``TabBar`` shows.
public struct TabBarLabel {
    public var icon: Image

    /// The icon's colour, as a file's says what kind it is. `nil` for the
    /// accent on the tab in front and a quiet one on the rest.
    public var iconColor: Color?

    public var title: String

    /// Smaller, after the title: what tells two tabs of one name apart.
    public var detail: String?

    /// Kept at the front of the bar, with no close button, so it is not closed
    /// by a stray click.
    public var isPinned: Bool

    /// Has changes that are not saved: a dot where the close button goes,
    /// until the pointer is over the tab.
    public var isDirty: Bool

    /// What it shows has gone, as a deleted file has: struck through.
    public var isGone: Bool

    /// Changes when the tab asks to be looked at, as a terminal's bell does.
    /// One not in front flashes; the one in front is being looked at.
    public var attention: Int

    /// Shown when the pointer rests on the tab.
    public var help: String?

    public init(
        icon: Image,
        iconColor: Color? = nil,
        title: String,
        detail: String? = nil,
        isPinned: Bool = false,
        isDirty: Bool = false,
        isGone: Bool = false,
        attention: Int = 0,
        help: String? = nil
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.detail = detail
        self.isPinned = isPinned
        self.isDirty = isDirty
        self.isGone = isGone
        self.attention = attention
        self.help = help
    }
}
