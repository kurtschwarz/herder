import AppKit
import SwiftUI

/// The part of a resize handle that takes the mouse: the resize cursor, the
/// drag and the double-click.
///
/// AppKit rather than a SwiftUI gesture because the window is movable by its
/// background. A SwiftUI gesture over a view that is not itself an `NSView` is
/// still background to AppKit, so the drag would pick the window up instead.
/// This view says it cannot move the window, which is the only way to refuse.
///
/// The cursor is a cursor rect rather than `onHover` with `NSCursor.push` and
/// `pop`: AppKit owns its lifetime, so it cannot stick when the pointer leaves
/// mid-drag or the view is swapped out.
struct ResizeHandleSurface: NSViewRepresentable {
    var axis: Axis = .horizontal

    /// Distance along `axis` since the drag began, once it has gone a few
    /// points. Vertically, up is positive, which is AppKit's and is the way a
    /// panel under the editor grows.
    let onDrag: (CGFloat) -> Void
    let onDragEnded: () -> Void
    let onDoubleClick: () -> Void
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> SurfaceView {
        SurfaceView()
    }

    func updateNSView(_ view: SurfaceView, context: Context) {
        view.axis = axis
        view.onDrag = onDrag
        view.onDragEnded = onDragEnded
        view.onDoubleClick = onDoubleClick
        view.onHover = onHover
    }

    final class SurfaceView: NSView {
        var axis: Axis = .horizontal {
            didSet { window?.invalidateCursorRects(for: self) }
        }
        var onDrag: (CGFloat) -> Void = { _ in }
        var onDragEnded: () -> Void = {}
        var onDoubleClick: () -> Void = {}
        var onHover: (Bool) -> Void = { _ in }

        /// A few points before a drag starts, so a double-click is not read as
        /// one.
        private let threshold: CGFloat = 3
        private var dragOrigin: CGFloat?
        private var isDragging = false

        override var mouseDownCanMoveWindow: Bool { false }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: axis == .horizontal ? .resizeLeftRight : .resizeUpDown)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(
                NSTrackingArea(
                    rect: bounds,
                    options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                    owner: self
                )
            )
        }

        private func position(of event: NSEvent) -> CGFloat {
            axis == .horizontal ? event.locationInWindow.x : event.locationInWindow.y
        }

        override func mouseEntered(with event: NSEvent) { onHover(true) }
        override func mouseExited(with event: NSEvent) { onHover(false) }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                onDoubleClick()
                dragOrigin = nil
            } else {
                // The window's coordinates, not this view's: the view moves as
                // the pane does, and a translation measured in it would not.
                dragOrigin = position(of: event)
            }
            isDragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let origin = dragOrigin else { return }
            let distance = position(of: event) - origin
            if !isDragging {
                guard abs(distance) >= threshold else { return }
                isDragging = true
            }
            onDrag(distance)
        }

        override func mouseUp(with event: NSEvent) {
            defer {
                dragOrigin = nil
                isDragging = false
            }
            if isDragging { onDragEnded() }
        }
    }
}
