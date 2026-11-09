import AppKit
import SwiftUI

/// Marks the view it is behind as having a double-click of its own, so the
/// window does not zoom when one lands on it. Takes no clicks itself: they go
/// to the SwiftUI view in front.
///
/// For a view that is not an `NSView`, which the window cannot otherwise tell
/// from its background. See ``HandlesDoubleClick``.
struct DoubleClickClaim: NSViewRepresentable {
    func makeNSView(context: Context) -> ClaimView {
        ClaimView()
    }

    func updateNSView(_ view: ClaimView, context: Context) {}

    final class ClaimView: NSView, HandlesDoubleClick {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
