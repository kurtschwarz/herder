import AppFeature
import SwiftUI

/// Entry point, nothing else.
///
/// This target's whole job is to declare scenes. Every service, every model and
/// every line of behaviour lives in `HerderKit`, and `AppEnvironment`
/// is what builds them — including the live services, which used to be
/// constructed here. The project file is generated from `project.yml`, so the
/// fewer files this target has, the less often it has to be regenerated.
@main
struct HerderApp: App {
    @State private var environment: AppEnvironment

    /// Asks before quitting with unsaved edits.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        _environment = State(initialValue: AppEnvironment())
    }

    var body: some Scene {
        WindowGroup(id: MainWindow.id) {
            AppView(environment: environment)
                // Reading the repository list touches the disk, so it happens
                // here rather than in `init`. The sidebar is empty for the
                // moment it takes.
                .task {
                    delegate.environment = environment
                    await environment.start()
                }
                // Quitting is the only way out, so this is where the sandbox
                // gets its folder access handed back.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    environment.stop()
                }
        }
        .defaultSize(width: 1180, height: 760)
        // The design puts the traffic lights inside the sidebar's header rather
        // than in a title bar of their own.
        .windowStyle(.hiddenTitleBar)
        .commands { AppCommands(updater: environment.updater) }

        // One of it, opened with ⌘, and not brought back on relaunch.
        Window("Settings", id: SettingsWindow.id) {
            SettingsWindow(environment: environment)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        // One of it, opened from Tools and not brought back on relaunch. It is
        // resizable, unlike settings, which has one column of controls.
        Window("Task Manager", id: TaskManagerWindow.id) {
            TaskManagerWindow(environment: environment)
        }
        .defaultSize(TaskManagerWindow.defaultSize)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
    }
}
