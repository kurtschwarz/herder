import AppKit
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

    /// Whether the window is open, so that a closed one reads nothing even if
    /// SwiftUI keeps its content around. Closing says no, and the window
    /// becoming the key one again says yes.
    @State private var isOpen = true
    @State private var host = Host()

    /// The window, once `WindowChrome` has handed it over.
    private final class Host {
        weak var window: NSWindow?
    }

    public init(environment: AppEnvironment) {
        _model = State(initialValue: environment.makeTaskManager())
    }

    public var body: some View {
        TaskManagerView(model: model, isPolling: isOpen)
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
            .background(
                WindowChrome(onClose: { isOpen = false }, onWindow: { host.window = $0 }, followsActiveSpace: true)
            )
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
                if let window = note.object as? NSWindow, window === host.window { isOpen = true }
            }
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
    }
}
