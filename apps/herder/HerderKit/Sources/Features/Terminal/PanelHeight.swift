import Foundation

/// How tall a panel under the editor is allowed to be.
///
/// Like ``PaneWidths``, what is stored is the user's intent, and this squeezes
/// it to the window at layout time without writing the result back: making the
/// window taller again gives the panel the height it was set to.
enum PanelHeight {
    struct Limits: Sendable, Equatable {
        /// What a panel that was never dragged measures.
        var defaultHeight: CGFloat
        var minimumPanel: CGFloat

        /// What the editor above is protected down to. A target: on a very
        /// short window the panel's own minimum wins.
        var minimumEditor: CGFloat

        init(defaultHeight: CGFloat, minimumPanel: CGFloat, minimumEditor: CGFloat) {
            self.defaultHeight = defaultHeight
            self.minimumPanel = minimumPanel
            self.minimumEditor = minimumEditor
        }
    }

    /// The height to draw: what was stored, or the default, held to the limits
    /// in `available`, the height the panel and the editor share.
    static func resolved(_ stored: CGFloat?, in available: CGFloat, limits: Limits) -> CGFloat {
        clamp(stored ?? limits.defaultHeight, in: available, limits: limits)
    }

    /// What to store for a drag that proposes `proposed`.
    static func clamp(_ proposed: CGFloat, in available: CGFloat, limits: Limits) -> CGFloat {
        let ceiling = max(limits.minimumPanel, available - limits.minimumEditor)
        return min(max(proposed, limits.minimumPanel), ceiling)
    }
}
