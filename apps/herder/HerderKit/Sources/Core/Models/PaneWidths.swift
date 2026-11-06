import Foundation

/// How wide the two outer panes are, as the user left them.
///
/// A width of `nil` means "never dragged": the pane takes whatever the default
/// is, so changing the default later moves everyone who never chose one. What is
/// stored is the user's intent, not what fits; ``resolved(in:limits:)`` squeezes
/// it to the window at layout time and never writes the result back, so
/// widening the window again gives the pane back the width it was set to.
public struct PaneWidths: Codable, Sendable, Equatable {
    public enum Side: Sendable {
        case leading
        case trailing
    }

    /// The numbers the pane layout is held to. Passed in rather than named here
    /// because they are design tokens, which `Core` cannot see.
    public struct Limits: Sendable, Equatable {
        /// What a pane that was never dragged measures.
        public var defaultWidth: CGFloat
        /// The narrowest a pane may be.
        public var minimumPane: CGFloat
        /// What the editor is protected down to while a pane is dragged or
        /// squeezed. A target, not a guarantee: two panes at their minimum can
        /// leave the editor less on a very small window.
        public var minimumEditor: CGFloat

        public init(defaultWidth: CGFloat, minimumPane: CGFloat, minimumEditor: CGFloat) {
            self.defaultWidth = defaultWidth
            self.minimumPane = minimumPane
            self.minimumEditor = minimumEditor
        }
    }

    public var leading: CGFloat?
    public var trailing: CGFloat?

    public init(leading: CGFloat? = nil, trailing: CGFloat? = nil) {
        self.leading = leading
        self.trailing = trailing
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        leading = try container.decodeIfPresent(CGFloat.self, forKey: .leading)
        trailing = try container.decodeIfPresent(CGFloat.self, forKey: .trailing)
    }

    /// The widths to draw, given the `available` width the two panes and the
    /// editor share (the gaps between them already taken off).
    ///
    /// If the stored widths leave the editor less than its minimum, both panes
    /// give up their width above the pane minimum in proportion, so the layout
    /// stays recognisably the one that was set. No pane goes below its minimum,
    /// which is why the editor can still end up under its own on a tiny window.
    public func resolved(in available: CGFloat, limits: Limits) -> (leading: CGFloat, trailing: CGFloat) {
        let minimum = limits.minimumPane
        let wantedLeading = max(leading ?? limits.defaultWidth, minimum)
        let wantedTrailing = max(trailing ?? limits.defaultWidth, minimum)

        let allowedTotal = max(available - limits.minimumEditor, 2 * minimum)
        guard wantedLeading + wantedTrailing > allowedTotal else {
            return (wantedLeading, wantedTrailing)
        }

        let surplus = (wantedLeading - minimum) + (wantedTrailing - minimum)
        let kept = (allowedTotal - 2 * minimum) / surplus
        return (
            minimum + (wantedLeading - minimum) * kept,
            minimum + (wantedTrailing - minimum) * kept
        )
    }

    /// These widths with `side` set towards `proposed`, held to the pane minimum
    /// and to what the other pane leaves the editor.
    public func setting(_ side: Side, to proposed: CGFloat, in available: CGFloat, limits: Limits) -> PaneWidths {
        let current = resolved(in: available, limits: limits)
        let other = side == .leading ? current.trailing : current.leading
        let maximum = max(available - limits.minimumEditor - other, limits.minimumPane)
        let width = min(max(proposed, limits.minimumPane), maximum)

        var result = self
        switch side {
        case .leading: result.leading = width
        case .trailing: result.trailing = width
        }
        return result
    }

    /// These widths with `side` back to the default.
    public func resetting(_ side: Side) -> PaneWidths {
        var result = self
        switch side {
        case .leading: result.leading = nil
        case .trailing: result.trailing = nil
        }
        return result
    }
}
