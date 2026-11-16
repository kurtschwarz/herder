import Core
import DesignSystem
import SwiftUI
import TaskManagerFeature

/// The Task Manager window: ``TaskManagerView`` on the same glass and chrome as
/// the settings window.
public struct TaskManagerWindow: View {
    /// What the scene is declared under and what Tools ▸ Task Manager opens.
    public static let id = "task-manager"

    /// What the window opens at: about the main window's size.
    public static let defaultSize = Theme.Size.taskManagerWindow

    /// Made when the window opens and dropped when it closes, so its history
    /// starts again each time and nothing holds it between.
    @State private var model: TaskManagerModel

    public init(environment: AppEnvironment) {
        _model = State(initialValue: environment.makeTaskManager())
    }

    public var body: some View {
        TaskManagerView(model: model)
            .frame(
                minWidth: Theme.Size.minTaskManagerWindow.width,
                maxWidth: .infinity,
                minHeight: Theme.Size.minTaskManagerWindow.height,
                maxHeight: .infinity
            )
            .background { WindowGlass() }
            // One window for the life of the app, so it follows the active
            // Space, as settings does, rather than pulling the person back to
            // the one it first opened on.
            .background(WindowChrome(followsActiveSpace: true))
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
    }
}
