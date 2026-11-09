import AppKit

/// A view that answers a double-click itself. The window zooms on a
/// double-click along its top edge, as a title bar would, except on one of
/// these.
public protocol HandlesDoubleClick: NSView {}
