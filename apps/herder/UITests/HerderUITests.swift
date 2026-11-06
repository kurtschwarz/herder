import XCTest

/// UI tests stay in XCTest: Swift Testing has no UI automation. Everything else is
/// a Swift Testing suite inside `HerderKit`.
final class HerderUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }
}
