import DesignSystem
import SwiftUI

/// One entry in the settings sidebar, and the pane it shows.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case agents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .agents: "Agents"
        }
    }

    /// The glyph on the pane's tile, drawn white over ``tint``.
    var glyph: Image {
        switch self {
        case .general: Ph.gearSixFill
        case .agents: Ph.sparkleFill
        }
    }

    var tint: LinearGradient {
        switch self {
        case .general: Theme.Gradient.graphiteTile
        case .agents: Theme.Gradient.violetTile
        }
    }
}
