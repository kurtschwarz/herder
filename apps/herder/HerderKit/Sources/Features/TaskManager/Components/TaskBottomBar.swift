import Core
import DesignSystem
import SwiftUI

/// What is selected, on the left, and what can be done to it, on the right.
///
/// Interrupt and End session are not here: both have to go through the window
/// that owns the session, so that it records how the session ended, and that
/// is not built yet. They are left out rather than shown dimmed.
struct TaskBottomBar: View {
    let model: TaskManagerModel

    var body: some View {
        HStack(spacing: Theme.Spacing.loose) {
            Text(model.selectionSummary ?? "Nothing selected")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.secondaryText)
                .lineLimit(1)

            Spacer(minLength: Theme.Spacing.loose)

            Button("Show session") { model.showSelectedSession() }
                .buttonStyle(.secondary)
                .disabled(!model.canShowSession)
        }
        .padding(.horizontal, TaskColumns.inset)
        .frame(height: 48)
    }
}
