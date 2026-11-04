import AppFeature
import Clients
import SwiftUI

/// Entry point and glue, nothing else.
///
/// This target's whole job is to declare scenes and inject live implementations of
/// the clients. All behaviour lives in `Packages/HerderKit`.
@main
struct HerderApp: App {
    @State private var model = AppModel(files: LiveFileClient())

    var body: some Scene {
        WindowGroup {
            AppView(model: model)
        }
        .defaultSize(width: 980, height: 620)
    }
}
