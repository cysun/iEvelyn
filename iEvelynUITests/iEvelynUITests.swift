import XCTest

final class iEvelynUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRootViewAppears() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        let rootView = app.staticTexts["library-root"]
        XCTAssertTrue(
            rootView.waitForExistence(timeout: 10),
            "The iEvelyn root view should be visible after launch."
        )
    }
}
