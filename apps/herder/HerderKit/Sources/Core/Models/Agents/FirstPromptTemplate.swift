import Foundation

/// What a New order's typed text becomes before an agent is told it: a
/// template the user wrote, with ``token`` standing for the text. For starting
/// every order with a skill, as `/grill-me {prompt}` does.
public enum FirstPromptTemplate {
    public static let token = "{prompt}"

    /// `text` in `template`. A template with no ``token`` comes first, then a
    /// blank line, then the text; a blank one leaves the text as it is.
    public static func apply(_ template: String, to text: String) -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        guard trimmed.contains(token) else { return trimmed + "\n\n" + text }
        return trimmed.replacing(token, with: text)
    }
}
