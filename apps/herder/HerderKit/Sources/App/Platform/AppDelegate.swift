import AppKit

/// Asks before the app quits with unsaved edits.
///
/// SwiftUI has no spelling for this: the only hook is
/// `applicationShouldTerminate`, which is also what makes a quit able to wait
/// while the files are written.
public final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Handed over by the app once it has built it, because the system makes
    /// this object, not the app.
    public var environment: AppEnvironment?

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let environment else { return .terminateNow }
        let files = environment.unsavedFiles
        guard !files.isEmpty else { return .terminateNow }

        switch UnsavedChangesAlert.choice(for: UnsavedChangesAlert.make(files: files).runModal()) {
        case .discard:
            return .terminateNow
        case .cancel:
            return .terminateCancel
        case .save:
            // Quitting waits for the writes, and does not happen at all if one
            // fails: the window shows why, and the edits are still there.
            Task {
                let saved = await environment.saveAll()
                sender.reply(toApplicationShouldTerminate: saved)
            }
            return .terminateLater
        }
    }
}
