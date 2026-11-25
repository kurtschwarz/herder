/// Which whitespace the editor draws a marker for, as `editor.show_whitespace`
/// spells it in `settings.json`.
public enum ShowWhitespace: String, Sendable, Equatable, CaseIterable {
    case none
    /// Spaces and tabs at the end of a line.
    case trailing
    /// Every space, tab and line ending.
    case all
}
