import AppKit

/// The question asked before a window closes or the app quits with files that
/// were edited and not saved: one prompt naming all of them.
enum UnsavedChangesAlert {
    enum Choice {
        case save, discard, cancel
    }

    /// How many names are listed before the rest are counted.
    private static let listed = 8

    static func make(files: [String]) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = files.count == 1
            ? "Do you want to save the changes to \u{201C}\(files[0])\u{201D}?"
            : "Do you want to save the changes to \(files.count) files?"

        var lines = files.prefix(listed).map { "\u{2022} \($0)" }
        if files.count > listed { lines.append("and \(files.count - listed) more") }
        alert.informativeText = (lines + ["", "Your changes will be lost if you don\u{2019}t save them."])
            .joined(separator: "\n")

        alert.addButton(withTitle: files.count == 1 ? "Save" : "Save All")
        alert.addButton(withTitle: "Don\u{2019}t Save")
        alert.addButton(withTitle: "Cancel")
        return alert
    }

    static func choice(for response: NSApplication.ModalResponse) -> Choice {
        switch response {
        case .alertFirstButtonReturn: .save
        case .alertSecondButtonReturn: .discard
        default: .cancel
        }
    }
}
