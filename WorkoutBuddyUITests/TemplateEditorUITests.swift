import XCTest

/// Smoke test of the phase 2 template editor, and a check that the settings are isolated per launch.
/// `nonisolated` because `XCTestCase`'s initializers and `setUp` are; the tests drive `XCUIApplication`,
/// which is main-actor API, so they are `@MainActor`.
nonisolated final class TemplateEditorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateWorkoutAndSeeItInTheList() {
        let app = launch()
        app.navigationBars.buttons["New Workout"].tapSettled()

        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: defaultTimeout))
        name.tapSettled()
        app.dismissKeyboardIntroductionIfPresent()
        name.typeSlowly("Smoke Test")

        app.buttons["Add Exercise"].tapSettled()
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 2) {
            // On iOS 18 the search field starts hidden above the list until it is pulled down.
            app.swipeDown()
        }
        XCTAssertTrue(search.waitForExistence(timeout: defaultTimeout))
        search.tapSettled()
        app.dismissKeyboardIntroductionIfPresent()
        search.typeSlowly("Bench")
        let benchPress = app.buttons["Bench Press"]
        XCTAssertTrue(benchPress.waitForExistence(timeout: defaultTimeout))
        benchPress.tapSettled()
        XCTAssertTrue(app.buttons["Bench Press, Added"].waitForExistence(timeout: defaultTimeout))
        app.dismissSearch()
        app.goBack(from: "Add Exercise")

        let row = app.buttons["Bench Press"]
        XCTAssertTrue(row.waitForExistence(timeout: defaultTimeout))
        row.tapSettled()
        let reps = app.otherElements["Reps"]
        XCTAssertTrue(reps.waitForExistence(timeout: defaultTimeout))
        XCTAssertEqual(reps.value as? String, "10")
        reps.incrementRepsStepper()
        XCTAssertTrue(reps.waitUntil("value == '11'"), "reps value: \(String(describing: reps.value))")

        app.goBack(from: "Bench Press")
        app.buttons["Save"].tapSettled()

        let listRow = app.buttons["Smoke Test"]
        XCTAssertTrue(listRow.waitForExistence(timeout: defaultTimeout))
        listRow.tapSettled()
        let start = app.buttons["Start Workout"]
        XCTAssertTrue(start.waitForExistence(timeout: defaultTimeout))
        XCTAssertTrue(start.isEnabled)
    }

    @MainActor
    func testSettingsAreIsolatedPerLaunch() {
        var app = launch()
        app.tabBars.buttons["Settings"].tapSettled()
        var reps = app.otherElements["Reps"]
        XCTAssertTrue(reps.waitForExistence(timeout: defaultTimeout))
        XCTAssertEqual(reps.value as? String, "10")
        reps.incrementRepsStepper()
        XCTAssertTrue(reps.waitUntil("value == '11'"), "reps value: \(String(describing: reps.value))")

        app.terminate()
        app = launch()
        app.tabBars.buttons["Settings"].tapSettled()
        reps = app.otherElements["Reps"]
        XCTAssertTrue(reps.waitForExistence(timeout: defaultTimeout))
        XCTAssertEqual(reps.value as? String, "10", "the settings suite must be cleared at launch")
    }
}
