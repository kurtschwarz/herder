import Core
import DesignSystem
import SwiftUI

/// A rate and a small bar under it, filled by how much of a core it is.
struct CPUCell: View {
    let percent: Double?

    var body: some View {
        HStack(spacing: Theme.Spacing.normal) {
            Text(TaskFormat.cpu(percent))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.text)
            Capsule()
                .fill(Theme.Palette.control)
                .frame(width: 44, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Palette.accent)
                        .frame(width: 44 * min(max((percent ?? 0) / 100, 0), 1), height: 4)
                }
        }
    }
}
