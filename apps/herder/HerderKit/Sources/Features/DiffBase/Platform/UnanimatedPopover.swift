import AppKit
import SwiftUI

/// A popover that appears and goes without the fade. SwiftUI's `.popover` has
/// no way to turn that off, so this puts an `NSPopover` behind the view it
/// should point at, which does (`animates`).
///
/// Dismissed the way the system's is: a click outside or Esc closes it, and
/// `isPresented` follows.
struct UnanimatedPopover<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ anchor: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isPresented = $isPresented

        if isPresented, coordinator.popover == nil {
            let host = NSHostingController(rootView: content())
            host.sizingOptions = .preferredContentSize

            let popover = NSPopover()
            popover.animates = false
            popover.behavior = .transient
            popover.contentViewController = host
            popover.delegate = coordinator
            coordinator.popover = popover
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        } else if !isPresented, let popover = coordinator.popover {
            popover.close()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        var popover: NSPopover?
        var isPresented: Binding<Bool>?

        func popoverDidClose(_ notification: Notification) {
            popover = nil
            isPresented?.wrappedValue = false
        }
    }
}
