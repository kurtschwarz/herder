import AppKit

/// A pointer shape a program asked for (OSC 22), named as the W3C names the
/// cursors that the sequence takes.
enum TerminalPointerShape: Equatable {
    case `default`, contextMenu, help, pointer, progress, wait, cell, crosshair, text, verticalText
    case alias, copy, move, noDrop, notAllowed, grab, grabbing, allScroll
    case colResize, rowResize, nResize, eResize, sResize, wResize
    case neResize, nwResize, seResize, swResize, ewResize, nsResize, neswResize, nwseResize
    case zoomIn, zoomOut

    /// The nearest cursor macOS has. A shape it has none like is the arrow.
    var cursor: NSCursor {
        switch self {
        case .pointer: .pointingHand
        case .text: .iBeam
        case .verticalText: .iBeamCursorForVerticalLayout
        case .crosshair, .cell: .crosshair
        case .contextMenu: .contextualMenu
        case .alias: .dragLink
        case .copy: .dragCopy
        case .noDrop, .notAllowed: .operationNotAllowed
        case .grab: .openHand
        case .grabbing: .closedHand
        case .colResize, .ewResize: .resizeLeftRight
        case .rowResize, .nsResize: .resizeUpDown
        case .nResize: .resizeUp
        case .sResize: .resizeDown
        case .eResize: .resizeRight
        case .wResize: .resizeLeft
        case .default, .help, .progress, .wait, .move, .allScroll,
             .neResize, .nwResize, .seResize, .swResize, .neswResize, .nwseResize,
             .zoomIn, .zoomOut:
            .arrow
        }
    }
}
