import Core
import DesignSystem
import SwiftUI
import TestSupport

/// The Task Manager window's content: tiles over a table over a bar.
///
/// Draws no backdrop and configures no window, like the settings view: those
/// are the composition root's.
public struct TaskManagerView: View {
    private let model: TaskManagerModel
    private let isPolling: Bool

    /// `isPolling` is whether the window is open to be read, which whoever
    /// owns the window says: the view cannot see it close.
    public init(model: TaskManagerModel, isPolling: Bool = true) {
        self.model = model
        self.isPolling = isPolling
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.normal) {
            // Clears the traffic lights, which sit in the corner.
            Text("Task Manager")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Size.titleBar)

            SummaryTiles(model: model)

            TaskToolbar(model: model)
                .padding(.top, Theme.Spacing.tight)

            VStack(spacing: 0) {
                ProcessTable(model: model)
                Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
                TaskBottomBar(model: model)
            }
            .glassPaneBackground()
        }
        .padding([.horizontal, .bottom], Theme.Spacing.windowPadding + Theme.Spacing.normal)
        .padding(.top, Theme.Spacing.windowPadding)
        // Tied to the view, so that a closed window reads nothing: the loop
        // ends when the view goes, or when the window says it has closed.
        .task(id: isPolling) {
            if isPolling { await model.run() }
        }
    }
}

#if DEBUG
#Preview {
    let monitor = StubProcessMonitorClient()
    TaskManagerView(model: TaskManagerModel(monitor: monitor, processes: RunningProcesses(), clock: VirtualClockClient()))
        .frame(width: Theme.Size.taskManagerWindow.width, height: Theme.Size.taskManagerWindow.height)
        .background { WindowGlass() }
        .preferredColorScheme(.dark)
}
#endif
