import DesignSystem

/// One character cell of the screen, with its colours already resolved.
///
/// What the emulator hands the renderer, so that nothing past `TerminalEmulator`
/// has to know what a palette index or an inverse attribute is.
struct TerminalCell: Equatable {
    struct Attributes: OptionSet, Equatable {
        let rawValue: UInt8

        static let bold = Attributes(rawValue: 1 << 0)
        static let italic = Attributes(rawValue: 1 << 1)
        static let faint = Attributes(rawValue: 1 << 2)
        static let underline = Attributes(rawValue: 1 << 3)
        static let strikethrough = Attributes(rawValue: 1 << 4)
        static let invisible = Attributes(rawValue: 1 << 5)
    }

    /// The grapheme cluster, or empty for a blank cell.
    var text = ""

    var foreground = Theme.Terminal.foreground

    /// `nil` is the terminal's own background, which is not painted.
    var background: Theme.Terminal.RGB?
    var attributes: Attributes = []
    var isSelected = false

    /// Which of its row's links this cell is part of, counting from one, or
    /// zero for none. See ``TerminalEmulator/link(atColumn:row:)``.
    var link = 0
}
