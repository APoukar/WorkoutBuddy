import XCTest

/// Ending a workout: the summary, Save, Back to Workout and Discard. All on "Long Rests", whose 600 s rests
/// can't end by themselves. Every wait is an expectation, never a sleep.
nonisolated final class SessionEndUITests: XCTestCase {
    private typealias ID = UITestingContract.Identifier
    private typealias Spoken = UITestingContract.Spoken

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Done on the first set, Skip Rest, then Pause → End Workout → confirm.
    @MainActor
    private func endEarlyWithOneSetDone(_ app: XCUIApplication) {
        app.startWorkout(named: UITestingContract.Workout.longRests)
        app.assertSetScreen(exercise: "Bench Press", position: Spoken.position(exercise: 1, of: 2, set: 1, of: 2))
        app.setScreen.buttons[ID.setDone].tap()
        app.assertRestScreen()
        app.restScreen.buttons["Skip Rest"].tap()
        app.assertSetScreen(exercise: "Bench Press", position: Spoken.position(exercise: 1, of: 2, set: 2, of: 2))
        app.pauseAndTapEndWorkout(from: app.setScreen)
        XCTAssertTrue(
            app.staticTexts[Spoken.endConfirmationTitle].waitForExistence(timeout: defaultTimeout),
            "no End Workout? question")
        app.tapConfirmationButton("End Workout", excluding: ID.pausedEndWorkout)
    }

    /// End early with one set done → summary → Save. Merged with the "Back to Workout after an early end" case
    /// (one launch fewer): the first summary goes back to the second set, ends again, and the second one is saved.
    @MainActor
    func testEndEarlyThenBackToWorkoutThenEndAgainAndSave() {
        let app = launch(scenario: UITestingContract.Scenario.templates)
        endEarlyWithOneSetDone(app)

        app.assertSummary(title: Spoken.workoutEnded)
        XCTAssertTrue(app.summaryLayer.staticTexts[Spoken.setsCompleted(1)].exists)
        XCTAssertTrue(app.summaryLayer.staticTexts[Spoken.setsNotPerformed(2)].exists)

        // Back to Workout reopens the second set, not the summary.
        app.summaryLayer.buttons[Spoken.backToWorkout].tap()
        XCTAssertTrue(app.summaryLayer.waitForNonExistence(), "the summary stayed after Back to Workout")
        app.assertSetScreen(exercise: "Bench Press", position: Spoken.position(exercise: 1, of: 2, set: 2, of: 2))

        // End again (Pause → End Workout → confirm) and save.
        app.pauseAndTapEndWorkout(from: app.setScreen)
        app.tapConfirmationButton("End Workout", excluding: ID.pausedEndWorkout)
        app.assertSummary(title: Spoken.workoutEnded)
        XCTAssertTrue(app.summaryLayer.staticTexts[Spoken.setsCompleted(1)].exists)
        XCTAssertTrue(app.summaryLayer.staticTexts[Spoken.setsNotPerformed(2)].exists)

        app.summaryLayer.buttons["Save"].tap()
        app.assertNoSessionLayer()
        // The workout's detail screen is still pushed under the cover; the list row is behind it.
        app.assertRowAfterSession(UITestingContract.Workout.longRests, valueContains: Spoken.lastDone)
    }

    /// Done on the last set goes to the summary; Back to Workout reopens that last set (Overhead Press) with
    /// its values; Done again returns to the summary. The kg is raised before the first Done so the reopened
    /// set and the final volume prove the values were kept: 600 + 500 + 8 x 42.5 = 1,440.
    @MainActor
    func testBackToWorkoutAfterLastSetReopensLastSet() {
        let app = launch(scenario: UITestingContract.Scenario.templates)
        app.startWorkout(named: UITestingContract.Workout.longRests)
        let positions = [
            ("Bench Press", Spoken.position(exercise: 1, of: 2, set: 1, of: 2)),
            ("Bench Press", Spoken.position(exercise: 1, of: 2, set: 2, of: 2)),
            ("Overhead Press", Spoken.position(exercise: 2, of: 2, set: 1, of: 1)),
        ]
        // Long Rests rests after every set, but the last one's Done goes straight to the summary.
        for (index, (exercise, position)) in positions.enumerated() {
            app.assertSetScreen(exercise: exercise, position: position)
            if index == positions.count - 1 {
                ValueControl(identifier: ID.kgControl, in: app.setScreen).increment()
            }
            app.setScreen.buttons[ID.setDone].tap()
            if index < positions.count - 1 {
                app.assertRestScreen()
                app.restScreen.buttons["Skip Rest"].tap()
            }
        }
        app.assertSummary(title: Spoken.workoutComplete)

        app.summaryLayer.buttons[Spoken.backToWorkout].tap()
        XCTAssertTrue(app.summaryLayer.waitForNonExistence(), "the summary stayed after Back to Workout")
        let last = positions[positions.count - 1]
        app.assertSetScreen(exercise: last.0, position: last.1)
        XCTAssertEqual(ValueControl(identifier: ID.kgControl, in: app.setScreen).value, "42.5 kilograms")
        XCTAssertEqual(ValueControl(identifier: ID.repsControl, in: app.setScreen).value, "8")

        app.setScreen.buttons[ID.setDone].tap()
        app.assertSummary(title: Spoken.workoutComplete)
        XCTAssertTrue(app.summaryLayer.staticTexts[Spoken.setsCompleted(3)].exists)
        XCTAssertEqual(app.summaryVolume.value as? String, Spoken.plannedVolumeWithLastSetRaised)
    }

    /// Nothing done: Start → Pause → End Workout asks "Discard Workout?" → Discard Workout closes the cover
    /// and nothing is saved.
    @MainActor
    func testEndWithNothingDoneDiscards() {
        let app = launch(scenario: UITestingContract.Scenario.templates)
        app.startWorkout(named: UITestingContract.Workout.longRests)
        app.assertSetScreen(exercise: "Bench Press", position: Spoken.position(exercise: 1, of: 2, set: 1, of: 2))
        app.pauseAndTapEndWorkout(from: app.setScreen)
        XCTAssertTrue(
            app.staticTexts[Spoken.discardConfirmationTitle].waitForExistence(timeout: defaultTimeout),
            "no Discard Workout? question")
        // The source button here is the paused overlay's End Workout, whose label differs from the confirmation's.
        app.tapConfirmationButton("Discard Workout", excluding: ID.pausedEndWorkout)

        app.assertNoSessionLayer()
        app.assertRowAfterSession(UITestingContract.Workout.longRests, valueContains: Spoken.notDoneYet)
    }

    /// Every set skipped: the summary says "Workout Ended" with the can't-save note and Discard Workout in
    /// place of Save; Discard Workout (confirmed) closes the cover.
    @MainActor
    func testEverySetSkippedCannotBeSavedAndIsDiscarded() {
        let app = launch(scenario: UITestingContract.Scenario.templates)
        app.startWorkout(named: UITestingContract.Workout.longRests)
        // Skip Set opens the next set without a rest; the third skip finishes the workout.
        let positions = [
            ("Bench Press", Spoken.position(exercise: 1, of: 2, set: 1, of: 2)),
            ("Bench Press", Spoken.position(exercise: 1, of: 2, set: 2, of: 2)),
            ("Overhead Press", Spoken.position(exercise: 2, of: 2, set: 1, of: 1)),
        ]
        for (exercise, position) in positions {
            app.assertSetScreen(exercise: exercise, position: position)
            app.setScreen.buttons["Skip Set"].tap()
        }

        app.assertSummary(title: Spoken.workoutEnded)
        XCTAssertTrue(app.summaryLayer.staticTexts[Spoken.cannotSaveNote].exists, "no can't-save note")
        XCTAssertFalse(app.summaryLayer.buttons["Save"].exists, "Save is offered for a workout with no done set")
        let discard = app.summaryLayer.buttons[ID.summaryDiscardWorkout]
        XCTAssertTrue(discard.exists, "no Discard Workout")
        discard.tap()
        XCTAssertTrue(
            app.staticTexts[Spoken.discardConfirmationTitle].waitForExistence(timeout: defaultTimeout),
            "no Discard Workout? question")
        app.tapConfirmationButton("Discard Workout", excluding: ID.summaryDiscardWorkout)

        app.assertNoSessionLayer()
        app.assertRowAfterSession(UITestingContract.Workout.longRests, valueContains: Spoken.notDoneYet)
    }
}
