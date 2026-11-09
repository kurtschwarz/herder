import AppKit
import Core
import Darwin

/// Offers to move a copy of Herder that is running from its disk image, or
/// from Downloads without having been moved, into `/Applications`, and
/// relaunches it from there.
///
/// Such a copy is not somewhere anything can point at (see ``AppLocation``),
/// so until it moves, opencode gets neither the theme nor the plugin. It asks
/// on every launch from there. Declining once is not a reason to keep running
/// from a disk image.
enum ApplicationMover {
    static func offerIfNeeded(bundle: URL = Bundle.main.bundleURL) {
        let location = AppLocation(bundle: bundle)
        guard location != .settled, ask(location) == .alertFirstButtonReturn else { return }

        let destination = URL(filePath: "/Applications", directoryHint: .isDirectory)
            .appending(path: bundle.lastPathComponent, directoryHint: .isDirectory)
        do {
            try move(bundle, to: destination)
            try relaunch(destination)
        } catch {
            fail(error)
        }
    }

    private static func ask(_ location: AppLocation) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = "Move Herder to your Applications folder?"
        let source = location == .diskImage ? "from its disk image" : "from your Downloads folder"
        alert.informativeText = """
            Herder is running \(source). Once it is in Applications it can \
            set opencode up to show its status in the sidebar, and it will \
            still be there after you eject or clean up.
            """
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        return alert.runModal()
    }

    private static func move(_ bundle: URL, to destination: URL) throws {
        let files = FileManager.default
        let target = destination.standardizedFileURL
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL?.standardizedFileURL == target }) {
            throw AlreadyRunning()
        }
        // To the Trash rather than deleted, because it is the user's.
        if files.fileExists(atPath: destination.path(percentEncoded: false)) {
            try files.trashItem(at: destination, resultingItemURL: nil)
        }
        try files.copyItem(at: bundle, to: destination)
        removeQuarantine(destination)
    }

    /// The copy carries the download's quarantine flag, and a quarantined app
    /// moved by anything but the Finder is translocated again. Gatekeeper
    /// has already passed this one, so the flag has done its job.
    private static func removeQuarantine(_ bundle: URL) {
        let name = "com.apple.quarantine"
        removexattr(bundle.path(percentEncoded: false), name, XATTR_NOFOLLOW)
        let items = FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: nil)
        while let item = items?.nextObject() as? URL {
            removexattr(item.path(percentEncoded: false), name, XATTR_NOFOLLOW)
        }
    }

    /// Opens the moved copy once this one has gone, so two never share the
    /// state files. The shell outlives the app, which is the point.
    private static func relaunch(_ destination: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [
            "-c", #"while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; exec /usr/bin/open "$2""#,
            "sh", String(getpid()), destination.path(percentEncoded: false),
        ]
        try process.run()
        NSApp.terminate(nil)
    }

    private static func fail(_ error: any Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Herder could not be moved to Applications."
        alert.informativeText = error is AlreadyRunning
            ? "Another copy of Herder is running from there. Quit it and try again."
            : "Drag Herder into the Applications folder yourself, then open it from there.\n\n\(error.localizedDescription)"
        alert.runModal()
    }

    private struct AlreadyRunning: Error {}
}
