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
        public nonisolated static let paneGap: CGFloat = 10
        /// Horizontal inset for content inside a pane.
        public static let paneInset: CGFloat = 16
    }

    public enum Size {
        /// What an outer pane measures until the user drags it.
        public static let defaultSidebarWidth: CGFloat = 236
        /// The narrowest an outer pane may be dragged; narrower and the
        /// indented rows of a file tree start to truncate.
        public static let minSidebarWidth: CGFloat = 180
        /// What a drag leaves the editor, roughly 80 columns of code and the
        /// gutter.
        public static let minEditorWidth: CGFloat = 400
        /// The grip drawn in the gap between panes: a short pill, centred.
        public static let gripLength: CGFloat = 44
        public static let gripThickness: CGFloat = 4
        /// Header strip tall enough to clear the traffic lights.
        public static let titleBar: CGFloat = 48
        /// The command bar over the panes beside the sidebar. A gap short of
        /// the title bar, so the panes under it start where the sidebar's
        /// header ends and their headers line up with its list.
        public static var commandBar: CGFloat { titleBar - Spacing.paneGap }
        /// The shortcut chip at the end of the command bar.
        public static let keycap: CGFloat = 22
        public static let wolfMark = CGSize(width: 15, height: 19.5)
        /// Width of a centred modal card, measured off the add-workspace mockup.
        public static let modalWidth: CGFloat = 480
        /// For a modal with a list in it.
        public static let wideModalWidth: CGFloat = 560
        /// Height of a field or button inside a modal.
        public static let control: CGFloat = 32
        /// Square hit area and hover plate of a glyph-only button.
        public static let iconButton: CGFloat = 28
        /// Width of the expand/collapse chevron's hit area. The worktree rows
        /// are indented from it so their icons line up with the workspace icon.
        public static let chevron: CGFloat = 20
        /// How far each level of a file tree steps in. Also the width of the
        /// chevron slot on a folder row, so a file's icon lines up with its
        /// sibling folders'.
        public static let treeIndent: CGFloat = 14
        /// Point size of code in the editor.
        public static let code: CGFloat = 12
        /// Width of the editor's line-number gutter.
        public static let gutter: CGFloat = 48
        /// Point size of text in the terminal. Its own token, though it matches
        /// `code` today, so the two can part ways without a hunt.
        public static let terminal: CGFloat = 12
        /// The shortest the terminal panel may be dragged.
        public static let minTerminalHeight: CGFloat = 120
        /// What the panel measures until the user drags it.
        public static let defaultTerminalHeight: CGFloat = 240
        /// What a drag leaves the editor above the panel: a breadcrumb, a tab
        /// bar and a few lines.
        public static let minEditorHeight: CGFloat = 160
        /// The dot on a tab with unsaved changes.
        public static let unsavedDot: CGFloat = 8
        /// The settings window. Fixed: it has one column of controls, and a
        /// wider window would only make the lines longer.
        public static let settingsWindow = CGSize(width: 780, height: 540)
        /// The Task Manager: wide for its seven columns, and free to grow.
        public static let taskManagerWindow = CGSize(width: 1180, height: 760)
        /// The least that keeps the tiles and the columns from overlapping.
        public static let minTaskManagerWindow = CGSize(width: 900, height: 520)
        /// The coloured tile beside a settings pane's name in the sidebar.
        public static let settingsIcon: CGFloat = 22
        /// The same tile at the head of the pane itself.
        public static let settingsHeaderIcon: CGFloat = 32
    }

    public enum Opacity {
        /// A file git ignores: still there, but not what the work is about.
        public static let ignored: Double = 0.45
    }

    public enum Radius {
        /// Matches the window's own corner so the two read as one shape.
        ///
        /// AppKit does not expose the window corner radius, so this was measured
        /// off a screenshot: the arc completes 30px from the window's top edge at
        /// 2x. It is a macOS 26 value; earlier systems round their windows less.
        public static let pane: CGFloat = 16
        public static let modal: CGFloat = 20
        /// The boxed group of fields inside a modal.
        public static let fieldGroup: CGFloat = 14
        /// Text fields, chips and buttons.
        public static let control: CGFloat = 9
    }

    /// What a terminal draws with. Not in `Palette` because it is not a surface
    /// or a label: a program running in it may ask for any of these by number.
    /// Tokyo Night, to sit with the rest.
    public enum Terminal {
        public struct RGB: Sendable, Equatable {
            public let red: UInt8
            public let green: UInt8
            public let blue: UInt8

            public init(_ hex: UInt32) {
                red = UInt8(hex >> 16 & 0xff)
                green = UInt8(hex >> 8 & 0xff)
                blue = UInt8(hex & 0xff)
            }

            public var color: Color {
                Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
            }
        }

        public static let foreground = RGB(0xc0caf5)

        /// What a program that asks for the default background is told, and
        /// the colour inverse text takes. Not painted: the terminal sits
        /// straight on the window, like the editor.
        public static let background = RGB(0x1a1b26)
        public static let cursor = RGB(0xc0caf5)

        /// Behind selected text.
        public static let selection = RGB(0x283457)

        /// The sixteen colours a program names with SGR 30-37 and 90-97, in
        /// that order: eight normal, then eight bright.
        public static let ansi: [RGB] = [
            RGB(0x15161e), RGB(0xf7768e), RGB(0x9ece6a), RGB(0xe0af68),
            RGB(0x7aa2f7), RGB(0xbb9af7), RGB(0x7dcfff), RGB(0xa9b1d6),
            RGB(0x7982a9), RGB(0xf7768e), RGB(0x9ece6a), RGB(0xe0af68),
            RGB(0x7aa2f7), RGB(0xbb9af7), RGB(0x7dcfff), RGB(0xc0caf5),
        ]
    }

    public enum Palette {
        /// The window itself. Panes sit on top of this.
        public static let window = Color(red: 28 / 255, green: 28 / 255, blue: 31 / 255, opacity: 0.97)

        /// The pane-resize grip, shown while its edge is hovered or dragged.
        public static let grip = Color.white.opacity(0.5)

        /// Dark wash over the blurred desktop. Light enough that the wallpaper's
        /// colour still reads through.
        public static let windowTint = Color(red: 28 / 255, green: 28 / 255, blue: 31 / 255, opacity: 0.55)

        public static let paneTop = Color(red: 27 / 255, green: 27 / 255, blue: 30 / 255, opacity: 0.94)
        public static let paneBottom = Color(red: 23 / 255, green: 24 / 255, blue: 28 / 255, opacity: 0.94)

        /// Faint violet cast over panes, the mockup's stand-in for glass.
        public static let glassTint = Color(red: 160 / 255, green: 130 / 255, blue: 255 / 255, opacity: 0.03)

        /// Top-edge highlight that reads as a light source above the window.
        public static let paneHighlight = Color.white.opacity(0.04)

        /// The same light catching the rim of a settings icon tile. Stronger
        /// than a pane's, because the tile is small and brightly filled.
        public static let tileHighlight = Color.white.opacity(0.35)

        public static let text = Color(red: 229 / 255, green: 229 / 255, blue: 234 / 255)
        public static let secondaryText = Color(red: 152 / 255, green: 152 / 255, blue: 159 / 255)
        public static let tertiaryText = Color(red: 128 / 255, green: 128 / 255, blue: 136 / 255)
        public static let accent = Color(red: 122 / 255, green: 162 / 255, blue: 247 / 255)

        /// The band behind the line the caret is on in the editor.
        public static let currentLine = Color.white.opacity(0.05)

        /// The markers the editor draws for whitespace. Dim, close to the
        /// gutter's line numbers, so they stay out of the code's way.
        public static let whitespace = tertiaryText.opacity(0.7)

        /// Folder glyphs and the primary button. Distinct from `accent`, which
        /// is the blue of interactive text.
        public static let violet = Color(red: 184 / 255, green: 156 / 255, blue: 240 / 255)

        /// Label on a violet fill.
        public static let onViolet = Color(red: 28 / 255, green: 20 / 255, blue: 46 / 255)

        /// Flat dimming over the window behind a modal.
        public static let scrim = Color.black.opacity(0.45)

        public static let modal = Color(red: 33 / 255, green: 33 / 255, blue: 37 / 255)
        public static let fieldGroup = Color(red: 29 / 255, green: 29 / 255, blue: 33 / 255)
        public static let field = Color(red: 19 / 255, green: 19 / 255, blue: 22 / 255)
        public static let control = Color.white.opacity(0.08)
        public static let controlPressed = Color.white.opacity(0.14)

        /// Hairline around modal surfaces and fields.
        public static let hairline = Color.white.opacity(0.09)

        public static let warning = Color(red: 255 / 255, green: 158 / 255, blue: 100 / 255)

        /// Something that needs resolving before work can go on, such as a
        /// merge conflict.
        public static let danger = Color(red: 247 / 255, green: 118 / 255, blue: 142 / 255)

        /// Something working as it should, such as an agent that is busy.
        public static let success = Color(red: 158 / 255, green: 206 / 255, blue: 106 / 255)

        /// The glyph colour for a file with this extension, lowercased.
        ///
        /// Here rather than in either feature because the file tree and the
        /// editor's tab bar both draw the same file and must agree on it, and
        /// a colour is a token however it is chosen.
        public static func fileIcon(forExtension ext: String) -> Color {
            switch ext {
            case "swift": warning
            case "md", "json", "yml", "yaml", "toml": accent
            case "png", "jpg", "jpeg", "gif", "svg", "pdf": violet
            default: tertiaryText
            }
        }

        /// Code colours, one per `SyntaxTokenKind`.
        ///
        /// Named for what the token is, not for the colour, so the mapping in
        /// `EditorFeature` reads as a list of pairings and a retheme is a change
        /// to the right-hand side only. `Syntax` does not import this module
        /// and this module does not import `Syntax`: the editor is the one place
        /// that knows both.
        ///
        /// Some pairs share a value on purpose. A number and a `true` are both
        /// literals and Tokyo Night gives them one orange; splitting them here
        /// would be a distinction without a difference.
        public enum Syntax {
            public static let comment = Color(red: 86 / 255, green: 95 / 255, blue: 137 / 255)
            public static let keyword = Color(red: 187 / 255, green: 154 / 255, blue: 247 / 255)
            public static let `operator` = Color(red: 137 / 255, green: 221 / 255, blue: 255 / 255)
            public static let punctuation = Color(red: 154 / 255, green: 165 / 255, blue: 206 / 255)
            public static let string = Color(red: 158 / 255, green: 206 / 255, blue: 106 / 255)
            public static let escape = Color(red: 180 / 255, green: 249 / 255, blue: 248 / 255)
            public static let number = Color(red: 255 / 255, green: 158 / 255, blue: 100 / 255)
            public static let constant = number
            public static let function = Color(red: 122 / 255, green: 162 / 255, blue: 247 / 255)
            public static let type = Color(red: 42 / 255, green: 195 / 255, blue: 222 / 255)
            public static let constructor = function

            /// A shade under `text`, so plain identifiers sit back and the
            /// things that were worth marking come forward.
            public static let variable = Color(red: 192 / 255, green: 202 / 255, blue: 245 / 255)

            public static let property = Color(red: 125 / 255, green: 207 / 255, blue: 255 / 255)
            public static let parameter = Color(red: 224 / 255, green: 175 / 255, blue: 104 / 255)

            /// `@MainActor`, `#[derive]`, `@Observable`: declaration markers,
            /// so the keyword colour.
            public static let attribute = keyword

            public static let tag = Color(red: 247 / 255, green: 118 / 255, blue: 142 / 255)
            public static let namespace = Color(red: 65 / 255, green: 166 / 255, blue: 181 / 255)
            public static let label = Color(red: 157 / 255, green: 124 / 255, blue: 216 / 255)
        }
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

        /// Fills for the settings icon tiles, one per pane, lighter at the top
        /// like System Settings'. Named for the colour, so a pane picks one
        /// rather than the theme knowing which panes exist.
        public static let graphiteTile = tile(
            Color(red: 169 / 255, green: 173 / 255, blue: 181 / 255),
            Color(red: 110 / 255, green: 115 / 255, blue: 124 / 255)
        )

        public static let violetTile = tile(
            Color(red: 190 / 255, green: 160 / 255, blue: 250 / 255),
            Color(red: 124 / 255, green: 88 / 255, blue: 214 / 255)
        )

        private static func tile(_ top: Color, _ bottom: Color) -> LinearGradient {
            LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
        }
    }

    public enum Shadow {
        public static let paneColor = Color.black.opacity(0.35)
        /// Half the mockup's 30px CSS blur: SwiftUI radius is roughly blur / 2.
        public static let paneRadius: CGFloat = 15
        public static let paneOffset: CGFloat = 10

        /// Large and soft: with no blur behind it, this is what separates the
        /// card from the dimmed window.
        public static let modalColor = Color.black.opacity(0.55)
        public static let modalRadius: CGFloat = 40
        public static let modalOffset: CGFloat = 20

        /// Small and close: a tab picked up out of its strip, not a card over
        /// a window.
        public static let liftColor = Color.black.opacity(0.4)
        public static let liftRadius: CGFloat = 6
        public static let liftOffset: CGFloat = 2

        /// Just enough to seat a settings icon tile on the surface under it.
        public static let tileColor = Color.black.opacity(0.3)
        public static let tileRadius: CGFloat = 1
        public static let tileOffset: CGFloat = 1
    }
}
