import XCTest

final class SimplyVidtorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesToRootView() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["SimplyVidtor"].waitForExistence(timeout: 5))
    }
}
