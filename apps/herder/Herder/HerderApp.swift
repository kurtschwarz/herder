import AppFeature
import SwiftUI

/// Entry point, nothing else.
///
/// This target's whole job is to declare scenes. Every service, every model and
/// every line of behaviour lives in `Packages/HerderKit`, and `AppEnvironment`
/// is what builds them — including the live services, which used to be
/// constructed here. The project file is generated from `project.yml`, so the
/// fewer files this target has, the less often it has to be regenerated.
@main
struct HerderApp: App {
    @State private var environment: AppEnvironment

    init() {
        let environment = AppEnvironment()
        // Before any scene exists: a view must never render a workspace the
        // sandbox has not been asked for yet.
        environment.start()
        _environment = State(initialValue: environment)
    }

    var body: some Scene {
        WindowGroup {
            AppView(environment: environment)
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
        .modelContainer(environment.container)
        .commands {
            // ⌘N already opens a new window.
            CommandGroup(after: .newItem) {
                Button("Add Workspace…") { environment.beginAddingWorkspace() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }
}
