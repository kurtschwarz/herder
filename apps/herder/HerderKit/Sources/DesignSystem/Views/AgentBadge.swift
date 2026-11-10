import SwiftUI

/// A small coloured tile standing for an agent: a glyph on a tint of its own
/// colour. There are no logos here, so a preset gets a hand-picked glyph and
/// any other agent the first letter of its name on a neutral tile.
public struct AgentBadge: View {
    private let id: String
    private let name: String
    private let size: CGFloat

    /// `id` is the agent's ``Agent/id``, which is what a preset is known by.
    public init(id: String, name: String, size: CGFloat = 22) {
        self.id = id
        self.name = name
        self.size = size
    }

    public var body: some View {
        let style = Self.style(forID: id, name: name)
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(style.color.opacity(0.2))
            .frame(width: size, height: size)
            .overlay {
                Text(style.glyph)
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(style.color)
            }
    }

    struct Style: Equatable {
        var glyph: String
        var color: Color
    }

    static func style(forID id: String, name: String) -> Style {
        switch id {
        case "claude-code": Style(glyph: "\u{273B}", color: Color(red: 232 / 255, green: 133 / 255, blue: 106 / 255))
        case "opencode": Style(glyph: "oc", color: Color(red: 122 / 255, green: 190 / 255, blue: 247 / 255))
        case "pi": Style(glyph: "\u{03C0}", color: Theme.Palette.success)
        case "codex": Style(glyph: "\u{25CE}", color: Color(red: 140 / 255, green: 150 / 255, blue: 245 / 255))
        default:
            Style(
                glyph: name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?",
                color: Theme.Palette.secondaryText
            )
        }
    }
}

#if DEBUG
#Preview {
    HStack {
        AgentBadge(id: "claude-code", name: "Claude Code")
        AgentBadge(id: "opencode", name: "opencode")
        AgentBadge(id: "pi", name: "Pi")
        AgentBadge(id: "codex", name: "Codex")
        AgentBadge(id: "custom", name: "Aider")
    }
    .padding()
    .background(Theme.Palette.modal)
}
#endif
