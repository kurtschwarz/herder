import Clients
import Observation

/// Composition root for the feature graph.
///
/// The app target builds this with live clients; tests build it with fakes. As
/// features arrive, construct their models here and hand them to `AppView`.
///
/// `@MainActor` is implicit: this target's default isolation is `MainActor`.
@Observable
public final class AppModel {
    private let files: any FileClient

    public init(files: any FileClient) {
        self.files = files
    }
}
