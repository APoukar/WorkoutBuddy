import XCTest

/// Placeholder that proves the UI test target runs. Step 2 of `docs/plans/ui-tests.md` replaces it.
/// `nonisolated` because `XCTestCase`'s initializers and `setUp` are; the tests themselves drive
/// `XCUIApplication`, which is main-actor API, so they are `@MainActor`.
nonisolated final class LaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launchArguments = [UITestingContract.Argument.uiTesting, "YES"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Workouts"].waitForExistence(timeout: 10))
    }
}
