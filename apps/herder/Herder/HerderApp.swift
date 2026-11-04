import AppFeature
import Clients
import Storage
import SwiftData
import SwiftUI

/// Entry point and glue, nothing else.
///
/// This target's whole job is to declare scenes and inject live implementations of
/// the clients. All behaviour lives in `Packages/HerderKit`.
@main
struct HerderApp: App {
    private let container = Self.makeContainer()
    @State private var model: AppModel

    init() {
        let model = AppModel(
            files: LiveFileClient(),
            bookmarks: LiveBookmarkClient(),
            git: LiveGitClient(),
            context: container.mainContext
        )
        // Before any scene exists: a view must never render a workspace the
        // sandbox has not been asked for yet.
        model.start()
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            AppView(model: model)
                // Quitting is the only way out, so this is where the sandbox
                // gets its folder access handed back.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.stop()
                }
        }
        .defaultSize(width: 1180, height: 760)
        // The design puts the traffic lights inside the sidebar's header rather
        // than in a title bar of their own.
        .windowStyle(.hiddenTitleBar)
        .modelContainer(container)
    }

    /// There is no app without its workspaces, and nothing useful to fall back
    /// to: an in-memory store would silently throw away everything the user adds.
    private static func makeContainer() -> ModelContainer {
        do {
            return try WorkspaceContainer.live()
        } catch {
            fatalError("Could not open the workspace store: \(error)")
        }
    }
}
