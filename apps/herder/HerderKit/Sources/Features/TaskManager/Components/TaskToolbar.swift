import Core
import DesignSystem
import SwiftUI

/// The All / Agents / Herder control and the filter field, above the table.
struct TaskToolbar: View {
    @Bindable var model: TaskManagerModel

    var body: some View {
        HStack(spacing: Theme.Spacing.normal) {
            Picker("Show", selection: $model.scope) {
                Text("All").tag(TaskFilter.Scope.all)
                Text("Agents").tag(TaskFilter.Scope.agents)
                Text("Herder").tag(TaskFilter.Scope.herder)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)

            Spacer(minLength: Theme.Spacing.loose)

            HStack(spacing: Theme.Spacing.normal) {
                PhIcon(Ph.magnifyingGlass, size: 13)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                TextField("Filter", text: $model.filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !model.filter.isEmpty {
                    Button {
                        model.filter = ""
                    } label: {
                        PhIcon(Ph.xBold, size: 10)
                            .foregroundStyle(Theme.Palette.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.normal + 2)
            .frame(width: 240, height: Theme.Size.control)
            .fieldSurface()
        }
    }
}
