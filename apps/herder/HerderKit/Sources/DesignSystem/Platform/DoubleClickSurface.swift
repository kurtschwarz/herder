import AppKit
import SwiftUI

/// Empty space that does something on a double-click, as a browser's tab strip
/// opens a tab, and still moves the window when dragged.
///
/// AppKit rather than a SwiftUI gesture, for the reason ``ResizeHandleSurface``
/// gives: the window is movable by its background, and takes the click first.
public struct DoubleClickSurface: NSViewRepresentable {
    private let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public func makeNSView(context: Context) -> SurfaceView {
        SurfaceView()
    }

    public func updateNSView(_ view: SurfaceView, context: Context) {
        view.action = action
    }

    public final class SurfaceView: NSView, HandlesDoubleClick {
        var action: () -> Void = {}

        override public var mouseDownCanMoveWindow: Bool { false }

        override public func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                action()
            } else {
                // Refusing to move the window is what lets the double-click
                // through, so the drag it would have done is done here.
                window?.performDrag(with: event)
            }
        }
    }
}
