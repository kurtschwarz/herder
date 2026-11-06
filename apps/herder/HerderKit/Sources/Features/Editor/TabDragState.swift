import Core
import Foundation

/// A tab being dragged along the strip: where it has got to, where it would
/// land, and how far each of the others has to shift to make room.
///
/// The strip is not reordered while the drag lasts. This is a draft over the
/// order the drag began with, and the model hears of it once, when the tab is
/// put down — so a drag that is cancelled has nothing to undo.
struct TabDragState: Equatable {
    /// How close to either end of the strip the pointer has to be before the
    /// strip scrolls to bring more of it into reach.
    static let edgeZone: CGFloat = 40

    let dragged: PathKey

    /// How far the pointer has moved along the strip since the drag began,
    /// scrolling included.
    var translation: CGFloat = 0

    private let order: [PathKey]
    private let widths: [CGFloat]
    private let spacing: CGFloat
    private let origin: Int

    /// `nil` when `key` has no tab in `order`. A tab with no measured width is
    /// treated as having none, which leaves it unmoved rather than failing.
    init?(dragging key: PathKey, in order: [PathKey], widths: [PathKey: CGFloat], spacing: CGFloat) {
        guard let origin = order.firstIndex(of: key) else { return nil }
        self.dragged = key
        self.order = order
        self.widths = order.map { widths[$0] ?? 0 }
        self.spacing = spacing
        self.origin = origin
    }

    /// Where the tab would be put down: the slot whose neighbours it has
    /// crossed the middle of. Never outside the strip.
    var targetIndex: Int {
        let center = midpoint(of: origin) + translation
        var target = origin
        if translation > 0 {
            while target + 1 < order.count, midpoint(of: target + 1) < center { target += 1 }
        } else {
            while target > 0, midpoint(of: target - 1) > center { target -= 1 }
        }
        return target
    }

    /// How far to draw the tab for `key` from where the strip has it.
    func offset(for key: PathKey) -> CGFloat {
        if key == dragged {
            // Held inside the strip, so it cannot be pulled off either end.
            let lowest = -leading(of: origin)
            let highest = totalWidth - leading(of: origin) - widths[origin]
            return min(max(translation, lowest), highest)
        }
        guard let index = order.firstIndex(of: key) else { return 0 }
        let room = widths[origin] + spacing
        let target = targetIndex
        if target > origin, index > origin, index <= target { return -room }
        if target < origin, index >= target, index < origin { return room }
        return 0
    }

    /// The tab to scroll into view when the pointer is at an edge of a strip
    /// `viewport` wide, or `nil` when it is not at one: the neighbour beyond
    /// where the tab would land, so the next slot comes into reach.
    func edgeScrollTarget(pointerX: CGFloat, viewport: CGFloat) -> (key: PathKey, leading: Bool)? {
        if pointerX < Self.edgeZone {
            return (order[max(targetIndex - 1, 0)], true)
        }
        if pointerX > viewport - Self.edgeZone {
            return (order[min(targetIndex + 1, order.count - 1)], false)
        }
        return nil
    }

    // MARK: - Layout

    private var totalWidth: CGFloat {
        widths.reduce(0, +) + spacing * CGFloat(max(order.count - 1, 0))
    }

    private func leading(of index: Int) -> CGFloat {
        widths[..<index].reduce(0) { $0 + $1 + spacing }
    }

    private func midpoint(of index: Int) -> CGFloat {
        leading(of: index) + widths[index] / 2
    }
}
