import AppKit
import DesignSystem
import SwiftUI

/// Lets the window's content run under the title bar and lines the traffic lights
/// up with the sidebar's header.
///
/// `.hiddenTitleBar` alone only hides the title bar's title and background; content
/// is still laid out beneath it. `.fullSizeContentView` reclaims the strip. Neither
/// has a SwiftUI spelling, hence reaching for the `NSWindow`.
struct WindowChrome: NSViewRepresentable {
    /// Called when the user closes the window. Not when the app quits: AppKit
    /// does not post the notification this listens for while terminating, which
    /// is the whole difference between a window being closed and a window
    /// merely going away with the app.
    var onClose: () -> Void = {}

    /// Holds the resize observer for as long as the view is alive.
    final class Coordinator {
        var observer: NSObjectProtocol?
        var closeObserver: NSObjectProtocol?
        var doubleClickMonitor: Any?
        var onClose: () -> Void = {}

        // Isolated so it can reach `observer`, which this module's default
        // `MainActor` isolation otherwise puts out of a nonisolated deinit's reach.
        isolated deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
            if let doubleClickMonitor {
                NSEvent.removeMonitor(doubleClickMonitor)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // The view has no window during `makeNSView`, so configure once it is in
        // the hierarchy.
        Task { configure(view.window, context.coordinator) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        configure(view.window, context.coordinator)
    }

    private func configure(_ window: NSWindow?, _ coordinator: Coordinator) {
        guard let window else { return }

        // Reassigned every time, because the closure captures the window's
        // state, which does not exist when the view is first made.
        coordinator.onClose = onClose
        if coordinator.closeObserver == nil {
            coordinator.closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak coordinator] _ in
                MainActor.assumeIsolated { coordinator?.onClose() }
            }
        }

        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Lets the backdrop's blur sample the desktop behind the window.
        window.isOpaque = false
        window.backgroundColor = .clear
        // With no title bar left to grab, the background becomes the drag handle.
        window.isMovableByWindowBackground = true

        // AppKit lays the buttons back out when the window resizes, so the
        // adjustment has to be reapplied rather than set once.
        if coordinator.observer == nil {
            coordinator.observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { notification in
                guard let window = notification.object as? NSWindow else { return }
                MainActor.assumeIsolated { Self.positionTrafficLights(in: window) }
            }
        }

        // The title bar accessory swallows clicks meant for SwiftUI content, and
        // there is no real title bar to double-click, so watch for the gesture
        // directly and zoom the window like a standard title bar would.
        if coordinator.doubleClickMonitor == nil {
            coordinator.doubleClickMonitor = NSEvent.addLocalMonitorForEvents(
                matching: .leftMouseDown
            ) { [weak window] event in
                guard let window,
                      event.window === window,
                      event.clickCount == 2,
                      event.locationInWindow.y >= window.frame.height - Self.headerHeight
                else { return event }
                window.zoom(nil)
                return event
            }
        }

        Self.growTitleBar(in: window)
        Self.positionTrafficLights(in: window)
    }

    /// Height of the strip along the window's top edge that acts as the title bar.
    private static var headerHeight: CGFloat {
        Theme.Spacing.windowPadding * 2 + Theme.Size.titleBar
    }

    /// Makes `NSTitlebarView` tall enough to contain the lowered traffic lights.
    ///
    /// Hit testing for the window buttons only descends into that view, so moving
    /// them past its bottom edge leaves them drawn but dead: the click falls
    /// through to the SwiftUI content behind. Adding an accessory is the only way
    /// found to grow it that keeps the buttons clickable — resizing the bar
    /// directly does not survive AppKit's own layout.
    ///
    /// The cost is that AppKit backs the taller bar with a full-width view that
    /// swallows clicks, so SwiftUI content in the header is not interactive.
    /// Collapsing that view reclaims the clicks but makes the buttons dead again,
    /// so the two cannot be had together this way.
    private static func growTitleBar(in window: NSWindow) {
        guard window.titlebarAccessoryViewControllers.isEmpty,
              let close = window.standardWindowButton(.closeButton),
              let bar = close.superview
        else { return }

        let extra = trafficLightCentre + close.frame.height / 2 - bar.frame.height
        guard extra > 0 else { return }

        let accessory = NSTitlebarAccessoryViewController()
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: extra).isActive = true
        accessory.view = spacer
        accessory.layoutAttribute = .bottom
        window.addTitlebarAccessoryViewController(accessory)
    }

    /// Centres the traffic lights in the sidebar header.
    ///
    /// Left alone they sit at the window's top-left corner, which is where the
    /// sidebar pane's rounded corner is, so they straddle its edge. AppKit offers
    /// no supported way to ask for a different position, so the buttons are moved
    /// directly. If the hierarchy ever changes shape this leaves them where macOS
    /// put them rather than misplacing them.
    private static func positionTrafficLights(in window: NSWindow) {
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
        guard buttons.count == 3, let bar = buttons[0].superview else { return }

        let targetLeft = Theme.Spacing.windowPadding + Theme.Spacing.paneInset
        let spacing = buttons[1].frame.minX - buttons[0].frame.minX

        for (index, button) in buttons.enumerated() {
            let size = button.frame.size
            let left = targetLeft + CGFloat(index) * spacing
            let topInset = trafficLightCentre - size.height / 2
            let top = bar.isFlipped ? topInset : bar.bounds.height - topInset - size.height
            button.setFrameOrigin(CGPoint(x: left, y: top))
        }
    }

    /// Distance from the window's top edge to the middle of the sidebar header.
    private static var trafficLightCentre: CGFloat {
        Theme.Spacing.windowPadding + Theme.Size.titleBar / 2
    }
}
