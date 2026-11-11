import Core
import DesignSystem
import SwiftUI

/// `+107 −19`: lines inserted in green and deleted in red.
struct ChangeChip: View {
    let changes: GitChangeSummary

    var body: some View {
        HStack(spacing: Theme.Spacing.tight + 2) {
            Text("+\(changes.insertions)")
                .foregroundStyle(Theme.Palette.success)
            Text("\u{2212}\(changes.deletions)")
                .foregroundStyle(Theme.Palette.danger)
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .padding(.horizontal, Theme.Spacing.normal)
        .padding(.vertical, 3)
        .background(Theme.Palette.control, in: Capsule())
        .help("Lines changed since this branch left the default branch")
    }
}
