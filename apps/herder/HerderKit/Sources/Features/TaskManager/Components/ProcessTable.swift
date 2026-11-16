import Core
import DesignSystem
import SwiftUI

/// The grouped process tree, under its column titles.
struct ProcessTable: View {
    let model: TaskManagerModel

    var body: some View {
        VStack(spacing: 0) {
            TaskTableHeader(model: model)
            Rectangle().fill(Theme.Palette.hairline).frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.lines) { line in
                        TaskTableRow(
                            line: line,
                            now: model.sampledAt,
                            isSelected: model.selection == line.id,
                            toggle: { model.toggleExpanded(line.id) },
                            select: { model.selection = line.id }
                        )
                    }
                }
                .padding(.vertical, Theme.Spacing.tight)
            }
        }
    }
}
