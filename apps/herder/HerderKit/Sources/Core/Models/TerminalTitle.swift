/// What a terminal tab is called.
///
/// One rule, so the name can be predicted: what is running in the foreground,
/// as it was typed, cut short. Not what the program says its title is, which
/// changes whenever one decides to.
public enum TerminalTitle {
    /// Longer than this is cut. About what fits a tab beside its buttons.
    public static let maxLength = 24

    /// What the shell is called when nothing is known yet, or the process is
    /// gone.
    public static let placeholder = "Terminal"

    public static func make(for process: PTYProcess?) -> String {
        guard let process else { return placeholder }
        return process.isShell ? process.name : truncated(process.commandLine)
    }

    static func truncated(_ text: String, to limit: Int = maxLength) -> String {
        let flattened = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard flattened.count > limit else { return flattened }
        return flattened.prefix(limit - 1).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }
}
