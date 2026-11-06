import AppKit
import Core

/// The question asked before a window closes or the app quits with commands
/// still running in its terminals: one prompt naming them. An idle shell is
/// not asked about.
enum RunningCommandsAlert {
    enum Action {
        case closeWindow
        case quit

        var verb: String {
            switch self {
            case .closeWindow: "Close"
            case .quit: "Quit"
            }
        }

        var consequence: String {
            switch self {
            case .closeWindow: "Closing the window will end"
            case .quit: "Quitting will end"
            }
        }
    }

    /// How many are listed before the rest are counted.
    private static let listed = 8

    static func make(commands: [String], action: Action) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = commands.count == 1
            ? "Do you want to \(action.verb.lowercased()) while \u{201C}\(TerminalTitle.truncated(commands[0], to: 40))\u{201D} is running?"
            : "Do you want to \(action.verb.lowercased()) while \(commands.count) commands are running?"

        var lines = commands.prefix(listed).map { "\u{2022} \(TerminalTitle.truncated($0, to: 60))" }
        if commands.count > listed { lines.append("and \(commands.count - listed) more") }
        let ending = commands.count == 1 ? "it" : "them"
        alert.informativeText = (commands.count == 1 ? [] : lines + [""]).joined(separator: "\n")
            + "\(action.consequence) \(ending)."

        alert.addButton(withTitle: action.verb)
        alert.addButton(withTitle: "Cancel")
        return alert
    }

    /// `true` to go ahead.
    static func confirms(_ response: NSApplication.ModalResponse) -> Bool {
        response == .alertFirstButtonReturn
    }
}
