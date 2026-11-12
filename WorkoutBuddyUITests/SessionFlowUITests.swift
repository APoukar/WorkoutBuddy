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
        app.setScreen.buttons[UITestingContract.Identifier.setDone].tapSettled()

        // 10 s rest: the second Bench Press set opens by itself.
        app.assertRestScreen()
        app.assertSetScreen(
            exercise: "Bench Press",
            position: UITestingContract.Spoken.position(exercise: 1, of: 2, set: 2, of: 2),
            timeout: autoAdvanceTimeout)
        XCTAssertFalse(app.restScreen.exists)

        // 0 s rest: the next exercise opens straight away, without a rest screen.
        app.setScreen.buttons[UITestingContract.Identifier.setDone].tapSettled()
        app.assertSetScreen(
            exercise: "Overhead Press",
            position: UITestingContract.Spoken.position(exercise: 2, of: 2, set: 1, of: 1))

        // The last set goes straight to the summary.
        app.setScreen.buttons[UITestingContract.Identifier.setDone].tapSettled()
        app.assertSummary(title: UITestingContract.Spoken.workoutComplete)
        XCTAssertTrue(app.summaryLayer.staticTexts[UITestingContract.Spoken.setsCompleted(3)].exists)
        // Also proves the English region applied: "1,420", not "1 420".
        let volume = app.summaryVolume
        XCTAssertTrue(volume.exists)
        XCTAssertEqual(volume.value as? String, UITestingContract.Spoken.plannedVolume)

        app.summaryLayer.buttons["Save"].tapSettled()
        app.assertNoSessionLayer()
        // The workout's detail screen is still pushed under the cover; the list row is behind it.
        app.assertRowAfterSession(UITestingContract.Workout.shortRests, valueContains: UITestingContract.Spoken.lastDone)
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
        app.setScreen.buttons[UITestingContract.Identifier.setDone].tapSettled()

        app.assertRestScreen()
        let skip = app.restScreen.buttons["Skip Rest"]
        XCTAssertTrue(skip.waitUntilSettledOrPresent(), "Skip Rest is missing, off screen or ambiguous")
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
        app.setScreen.buttons[UITestingContract.Identifier.setDone].tapSettled()
        app.assertRestScreen()
        app.restScreen.buttons["Skip Rest"].tapSettled()
        XCTAssertTrue(app.setScreen.waitForExistence(timeout: defaultTimeout))
        app.setScreen.buttons["Pause"].tapSettled()
        XCTAssertTrue(app.pausedLayer.waitForExistence(timeout: defaultTimeout))
        app.pausedLayer.buttons[UITestingContract.Identifier.pausedEndWorkout].tapSettled()

        app.cancelConfirmation(label: "End Workout", excluding: UITestingContract.Identifier.pausedEndWorkout)
        XCTAssertTrue(app.pausedLayer.exists)
        XCTAssertTrue(app.pausedLayer.buttons["Resume"].exists)
    }

    // MARK: Set actions, rest actions and pause

    /// − / + on reps and kg, then a typed kg value, each saved by Done. Merged into one launch: the buttons
    /// on the first set, the keyboard on the second. The summary volume proves what was saved:
    /// 11 × 62.5 + 8 × 57.5 + 8 × 40 = 687.5 + 460 + 320.
    @MainActor
    func testAdjustedAndTypedValuesAreSavedByDone() {
        let app = launch(scenario: UITestingContract.Scenario.templates)
        app.startWorkout(named: UITestingContract.Workout.longRests)
        app.assertSetScreen(
            exercise: "Bench Press",
            position: UITestingContract.Spoken.position(exercise: 1, of: 2, set: 1, of: 2))

        // First set: planned 10 × 60. Reps 10 + 1 + 1 - 1 = 11, kg 60 + 2.5 = 62.5 (the default step).
        let reps = ValueControl(identifier: UITestingContract.Identifier.repsControl, in: app.setScreen)
        let kg = ValueControl(identifier: UITestingContract.Identifier.kgControl, in: app.setScreen)
        XCTAssertEqual(reps.value, "10")
        XCTAssertEqual(kg.value, "60 kilograms")
        reps.increment()
        reps.increment()
        reps.decrement()
        kg.increment()
        XCTAssertEqual(reps.value, "11")
        XCTAssertEqual(kg.value, "62.5 kilograms")
        app.setScreen.buttons[UITestingContract.Identifier.setDone].tapSettled()
        app.assertRestScreen()
        app.restScreen.buttons["Skip Rest"].tapSettled()

        // Second set: planned 8 × 62.5, typed 57.5.
        app.assertSetScreen(
            exercise: "Bench Press",
            position: UITestingContract.Spoken.position(exercise: 1, of: 2, set: 2, of: 2))
        let kg2 = ValueControl(identifier: UITestingContract.Identifier.kgControl, in: app.setScreen)
        XCTAssertEqual(kg2.value, "62.5 kilograms")
        kg2.focusField()
        app.dismissKeyboardIntroductionIfPresent()
        kg2.type("57.5", deleting: 8)
        let keyboardDone = app.toolbars.buttons["Done"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: defaultTimeout), "no keyboard Done bar")
        keyboardDone.tap()
        XCTAssertTrue(keyboardDone.waitForNonExistence(), "the keyboard didn't close")
        XCTAssertEqual(kg2.value, "57.5 kilograms")
        app.setScreen.buttons[UITestingContract.Identifier.setDone].tapSettled()

        // "Long Rests" rests after every set, so the last Bench Press set is followed by a rest; then
        // Overhead Press opens, done as planned.
        app.assertRestScreen()
        app.restScreen.buttons["Skip Rest"].tapSettled()
        app.assertSetScreen(
            exercise: "Overhead Press",
            position: UITestingContract.Spoken.position(exercise: 2, of: 2, set: 1, of: 1))
        app.setScreen.buttons[UITestingContract.Identifier.setDone].tapSettled()

        app.assertSummary(title: UITestingContract.Spoken.workoutComplete)
        let volume = app.summaryVolume
        XCTAssertTrue(volume.exists)
        XCTAssertEqual(volume.value as? String, "1,467.5 kilograms")
    }

    /// Skip Set goes straight to the next set (no rest screen), and Pause / Resume on the set screen.
    /// Merged into one launch: the pause check runs on the set the skip opened.
    @MainActor
    func testSkipSetSkipsRestAndPauseResumesOnSetScreen() {
        let app = launch(scenario: UITestingContract.Scenario.templates)
        app.startWorkout(named: UITestingContract.Workout.longRests)
        app.assertSetScreen(
            exercise: "Bench Press",
            position: UITestingContract.Spoken.position(exercise: 1, of: 2, set: 1, of: 2))

        app.setScreen.buttons["Skip Set"].tapSettled()
        app.assertSetScreen(
            exercise: "Bench Press",
            position: UITestingContract.Spoken.position(exercise: 1, of: 2, set: 2, of: 2))
        XCTAssertFalse(app.restScreen.exists, "Skip Set opened a rest screen")

        app.pauseAndResume(from: app.setScreen)
        app.assertSetScreen(
            exercise: "Bench Press",
            position: UITestingContract.Spoken.position(exercise: 1, of: 2, set: 2, of: 2))
    }

    /// Done opens the rest screen naming the next set; Pause / Resume there leaves it in place; Undo returns to
    /// the first set with the reps entered before Done; Done again and Skip Rest open the second set.
    /// Merged into one launch: all four steps are one flow on the same rest.
    @MainActor
    func testRestScreenUpNextPauseUndoAndSkipRest() {
        let app = launch(scenario: UITestingContract.Scenario.templates)
        app.startWorkout(named: UITestingContract.Workout.longRests)
        app.assertSetScreen(
            exercise: "Bench Press",
            position: UITestingContract.Spoken.position(exercise: 1, of: 2, set: 1, of: 2))
        let reps = ValueControl(identifier: UITestingContract.Identifier.repsControl, in: app.setScreen)
        let kg = ValueControl(identifier: UITestingContract.Identifier.kgControl, in: app.setScreen)
        reps.increment()
        kg.increment()
        XCTAssertEqual(reps.value, "11")
        XCTAssertEqual(kg.value, "62.5 kilograms")
        app.setScreen.buttons[UITestingContract.Identifier.setDone].tapSettled()

        app.assertRestScreen()
        let upNext = app.restScreen.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", UITestingContract.Spoken.upNextLabel)).firstMatch
        XCTAssertTrue(upNext.waitForExistence(timeout: defaultTimeout), "no Up next")
        XCTAssertEqual(upNext.value as? String, UITestingContract.Spoken.longRestsUpNextSet2)

        // Pause on the rest screen, then Resume: the rest screen is still there.
        app.pauseAndResume(from: app.restScreen)
        app.assertRestScreen()

        // Undo: the first set again, with the 11 reps entered before Done.
        app.restScreen.buttons["Undo"].tapSettled()
        app.assertSetScreen(
            exercise: "Bench Press",
            position: UITestingContract.Spoken.position(exercise: 1, of: 2, set: 1, of: 2))
        XCTAssertFalse(app.restScreen.exists)
        let repsAfterUndo = ValueControl(identifier: UITestingContract.Identifier.repsControl, in: app.setScreen)
        let kgAfterUndo = ValueControl(identifier: UITestingContract.Identifier.kgControl, in: app.setScreen)
        XCTAssertEqual(repsAfterUndo.value, "11")
        XCTAssertEqual(kgAfterUndo.value, "62.5 kilograms")

        app.setScreen.buttons[UITestingContract.Identifier.setDone].tapSettled()
        app.assertRestScreen()
        app.restScreen.buttons["Skip Rest"].tapSettled()
        app.assertSetScreen(
            exercise: "Bench Press",
            position: UITestingContract.Spoken.position(exercise: 1, of: 2, set: 2, of: 2))
        XCTAssertFalse(app.restScreen.exists)
    }
}
