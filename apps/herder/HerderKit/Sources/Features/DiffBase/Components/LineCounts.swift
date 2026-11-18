import DesignSystem
import SwiftUI

/// `+N −M`, in the added and removed colours.
struct LineCounts: View {
    let insertions: Int
    let deletions: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.tight) {
            Text("+\(insertions)").foregroundStyle(Theme.Palette.success)
            Text("\u{2212}\(deletions)").foregroundStyle(Theme.Palette.danger)
        }
        .font(.system(size: 11, design: .monospaced))
        .lineLimit(1)
    }
}
