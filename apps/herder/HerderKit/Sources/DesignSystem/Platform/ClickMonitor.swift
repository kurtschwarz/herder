import AppKit

/// Calls back on a mouse-down anywhere in the window outside the text being
/// edited, and lets the click carry on to what it was aimed at.
///
/// Focus leaves a text field only for something that takes it, and most of
/// the window does not, so a field being edited in place ends its edit with
/// this instead.
@MainActor
final class ClickMonitor {
    private var token: Any?

    init() {}

    func start(onOutsideClick: @escaping () -> Void) {
        stop()
        token = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            MainActor.assumeIsolated {
                // The field editor is the one text view AppKit lends the
                // field while it is being typed in.
                if let editor = event.window?.firstResponder as? NSTextView, editor.isFieldEditor,
                   editor.bounds.contains(editor.convert(event.locationInWindow, from: nil))
                {
                    return
                }
                onOutsideClick()
            }
            return event
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }

    isolated deinit { stop() }
}
