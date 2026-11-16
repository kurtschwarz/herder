import Foundation

/// A tab being dragged along a strip: where it has got to, where it would
/// land, and how far each of the others has to shift to make room.
///
/// The strip is not reordered while the drag lasts. This is a draft over the
/// order the drag began with, and the model hears of it once, when the tab is
/// put down — so a drag that is cancelled has nothing to undo.
public struct TabDragState<ID: Hashable>: Equatable {
    /// How close to either end of the strip the pointer has to be before the
    /// strip scrolls to bring more of it into reach.
    public static var edgeZone: CGFloat { 40 }

    public let dragged: ID

    /// How far the pointer has moved along the strip since the drag began,
    /// scrolling included.
    public var translation: CGFloat = 0

    private let order: [ID]
    private let widths: [CGFloat]
    private let spacing: CGFloat
    private let origin: Int
    private let run: ClosedRange<Int>

    /// `nil` when `id` has no tab in `order`. A tab with no measured width is
    /// treated as having none, which leaves it unmoved rather than failing.
    /// `run` is the slots it may land in, the whole strip if not given: see
    /// ``TabOrder``.
    public init?(
        dragging id: ID,
        in order: [ID],
        widths: [ID: CGFloat],
        spacing: CGFloat,
        within run: ClosedRange<Int>? = nil
    ) {
        guard let origin = order.firstIndex(of: id) else { return nil }
        self.dragged = id
        self.order = order
        self.widths = order.map { widths[$0] ?? 0 }
        self.spacing = spacing
        self.origin = origin
        self.run = run.map { $0.clamped(to: 0...(order.count - 1)) } ?? 0...(order.count - 1)
    }

    /// Where the tab would be put down: the slot whose neighbours it has
    /// crossed the middle of. Never outside its run.
    public var targetIndex: Int {
        let center = midpoint(of: origin) + translation
        var target = origin
        if translation > 0 {
            while target + 1 <= run.upperBound, midpoint(of: target + 1) < center { target += 1 }
        } else {
            while target - 1 >= run.lowerBound, midpoint(of: target - 1) > center { target -= 1 }
        }
        return target
    }

    /// How far to draw the tab for `id` from where the strip has it.
    public func offset(for id: ID) -> CGFloat {
        if id == dragged {
            // Held inside its run, so it cannot be pulled off either end or
            // across the pinned tabs.
            let lowest = leading(of: run.lowerBound) - leading(of: origin)
            let highest = leading(of: run.upperBound) + widths[run.upperBound] - leading(of: origin) - widths[origin]
            return min(max(translation, lowest), highest)
        }
        guard let index = order.firstIndex(of: id) else { return 0 }
        let room = widths[origin] + spacing
        let target = targetIndex
        if target > origin, index > origin, index <= target { return -room }
        if target < origin, index >= target, index < origin { return room }
        return 0
    }

    /// The tab to scroll into view when the pointer is at an edge of a strip
    /// `viewport` wide, or `nil` when it is not at one: the neighbour beyond
    /// where the tab would land, so the next slot comes into reach.
    public func edgeScrollTarget(pointerX: CGFloat, viewport: CGFloat) -> (id: ID, leading: Bool)? {
        if pointerX < Self.edgeZone {
            return (order[max(targetIndex - 1, 0)], true)
        }
        if pointerX > viewport - Self.edgeZone {
            return (order[min(targetIndex + 1, order.count - 1)], false)
        }
        return nil
    }

    // MARK: - Layout

    private func leading(of index: Int) -> CGFloat {
        widths[..<index].reduce(0) { $0 + $1 + spacing }
    }

    private func midpoint(of index: Int) -> CGFloat {
        leading(of: index) + widths[index] / 2
    }
}
