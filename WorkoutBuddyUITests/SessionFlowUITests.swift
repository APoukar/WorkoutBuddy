import XCTest

/// The phase 3 session flows, from the Workouts list to the saved workout. Every wait is an expectation, never a sleep.
nonisolated final class SessionFlowUITests: XCTestCase {
    /// The rest screen's own 10 s plus the app load on a slow runner.
    private let autoAdvanceTimeout: TimeInterval = 25

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDoneRestAutoAdvanceToSummaryAndSave() {
        let app = launch(scenario: UITestingContract.Scenario.templates)
        app.startWorkout(named: UITestingContract.Workout.shortRests)

        app.assertSetScreen(
            exercise: "Bench Press",
            position: UITestingContract.Spoken.position(exercise: 1, of: 2, set: 1, of: 2))
        app.setScreen.buttons[UITestingContract.Identifier.setDone].tap()

        // 10 s rest: the second Bench Press set opens by itself.
        app.assertRestScreen()
        app.assertSetScreen(
            exercise: "Bench Press",
            position: UITestingContract.Spoken.position(exercise: 1, of: 2, set: 2, of: 2),
            timeout: autoAdvanceTimeout)
        XCTAssertFalse(app.restScreen.exists)

        // 0 s rest: the next exercise opens straight away, without a rest screen.
        app.setScreen.buttons[UITestingContract.Identifier.setDone].tap()
        app.assertSetScreen(
            exercise: "Overhead Press",
            position: UITestingContract.Spoken.position(exercise: 2, of: 2, set: 1, of: 1))

        // The last set goes straight to the summary.
        app.setScreen.buttons[UITestingContract.Identifier.setDone].tap()
        app.assertSummary(title: UITestingContract.Spoken.workoutComplete)
        XCTAssertTrue(app.summaryLayer.staticTexts[UITestingContract.Spoken.setsCompleted(3)].exists)
        // Also proves the English region applied: "1,420", not "1 420".
        let volume = app.summaryLayer.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", UITestingContract.Spoken.volumeLabel)).firstMatch
        XCTAssertTrue(volume.exists)
        XCTAssertEqual(volume.value as? String, UITestingContract.Spoken.plannedVolume)

        app.summaryLayer.buttons["Save"].tap()
        XCTAssertTrue(app.summaryLayer.waitForNonExistence(), "the session cover didn't close")
        // The workout's detail screen is still pushed under the cover; the list row is behind it.
        app.goBack(from: UITestingContract.Workout.shortRests)
        let row = app.buttons[UITestingContract.Workout.shortRests]
        XCTAssertTrue(row.waitForExistence(timeout: defaultTimeout))
        XCTAssertTrue(
            row.waitUntil("value CONTAINS '\(UITestingContract.Spoken.lastDone)'"),
            "row value: \(String(describing: row.value))")
    }

    /// The rest screen's progress ring is a `TimelineView(.animation)`, which could keep the app from ever
    /// being idle and stall every XCUITest action on that screen. "Long Rests" so the rest can't end by itself.
    /// A normal tap takes about 2 s; a real idle stall takes tens of seconds, so 10 s tells them apart without
    /// failing on a slow runner.
    @MainActor
    func testRestScreenRespondsQuickly() {
        let app = launch(scenario: UITestingContract.Scenario.templates)
        app.startWorkout(named: UITestingContract.Workout.longRests)
        XCTAssertTrue(app.setScreen.waitForExistence(timeout: defaultTimeout))
        app.setScreen.buttons[UITestingContract.Identifier.setDone].tap()

        app.assertRestScreen()
        let skip = app.restScreen.buttons["Skip Rest"]
        let start = Date()
        skip.tap()
        let tapDuration = Date().timeIntervalSince(start)
        XCTAssertTrue(app.setScreen.waitForExistence(timeout: defaultTimeout))
        XCTAssertLessThan(tapDuration, 10, "Skip Rest took \(tapDuration) s: the rest screen keeps the app busy")
        XCTAssertFalse(app.restScreen.exists)
    }

    /// The confirmation can be cancelled (a Cancel button on iOS 18, the popover's dismiss region on iOS 26+).
    @MainActor
    func testCancelConfirmationKeepsWorkoutPaused() {
        let app = launch(scenario: UITestingContract.Scenario.templates)
        app.startWorkout(named: UITestingContract.Workout.longRests)
        app.setScreen.buttons[UITestingContract.Identifier.setDone].tap()
        app.assertRestScreen()
        app.restScreen.buttons["Skip Rest"].tap()
        XCTAssertTrue(app.setScreen.waitForExistence(timeout: defaultTimeout))
        app.setScreen.buttons["Pause"].tap()
        XCTAssertTrue(app.pausedLayer.waitForExistence(timeout: defaultTimeout))
        app.pausedLayer.buttons[UITestingContract.Identifier.pausedEndWorkout].tap()

        app.cancelConfirmation(label: "End Workout", excluding: UITestingContract.Identifier.pausedEndWorkout)
        XCTAssertTrue(app.pausedLayer.exists)
        XCTAssertTrue(app.pausedLayer.buttons["Resume"].exists)
    }
}
