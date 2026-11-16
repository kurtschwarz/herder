import Core
import DesignSystem
import SwiftUI

/// The widths of the table's columns, shared by its header and its rows so
/// that they line up. Name takes what is left.
enum TaskColumns {
    static let status: CGFloat = 112
    static let cpu: CGFloat = 138
    static let memory: CGFloat = 92
    static let threads: CGFloat = 72
    static let processes: CGFloat = 64
    static let uptime: CGFloat = 92

    /// What a row's text is inset by at each end.
    static let inset: CGFloat = Theme.Spacing.loose
}
