import ClientsTestSupport
import Testing

@testable import AppFeature

/// A struct suite gives every test a fresh instance, so state can't leak between
/// tests and there's no `setUp`/`tearDown` to keep in sync.
@Suite struct AppModelTests {
    let files = InMemoryFileClient()
    let model: AppModel

    init() {
        model = AppModel(files: files)
    }

    @Test func buildsWithFakeClients() {
        #expect(files.files.isEmpty)
    }
}
