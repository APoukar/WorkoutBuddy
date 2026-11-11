import XCTest

/// Recovery after a kill: the launch alert, and a real terminate-and-relaunch on the disk store.
nonisolated final class RecoveryUITests: XCTestCase {
    private typealias ID = UITestingContract.Identifier
    private typealias Spoken = UITestingContract.Spoken
    private let longRests = UITestingContract.Workout.longRests

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Waits for the recovery alert, checks its title and message, and returns it.
    @MainActor
    @discardableResult
    private func assertRecoveryAlert(
        _ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        let alert = app.alerts[Spoken.recoveryTitle]
        XCTAssertTrue(alert.waitForExistence(timeout: defaultTimeout), "no recovery alert", file: file, line: line)
        XCTAssertTrue(
            alert.staticTexts[Spoken.recoveryMessage(workout: longRests)].exists,
            "the alert doesn't name \(longRests)", file: file, line: line)
        // Positive control: the list is there behind the alert, so the missing layers mean "not presented".
        XCTAssertTrue(app.buttons[longRests].exists, "no \(longRests) row behind the alert", file: file, line: line)
        // The cover is presented only after the alert is answered.
        for layer in [app.setScreen, app.restScreen, app.reviewLayer, app.pausedLayer, app.summaryLayer] {
            XCTAssertFalse(layer.exists, "a session layer exists before the alert is answered", file: file, line: line)
        }
        return alert
    }

    /// Reads the rest countdown: a static text labelled like "Rest remaining, 9:37" (no value), as seconds.
    @MainActor
    private func remainingSeconds(_ app: XCUIApplication) -> Int? {
        let ring = app.restScreen.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", Spoken.restRemainingLabel)).firstMatch
        guard ring.waitForExistence(timeout: defaultTimeout) else { return nil }
        guard let match = ring.label.firstMatch(of: /(\d+):(\d{2})/) else { return nil }
        return Int(match.1)! * 60 + Int(match.2)!
    }

    @MainActor
    func testAlertNamesWorkoutAndResumeOpensCurrentSet() {
        let app = launch(scenario: UITestingContract.Scenario.inProgress)
        let alert = assertRecoveryAlert(app)
        XCTAssertTrue(alert.buttons[Spoken.resume].exists)
        XCTAssertTrue(alert.buttons[Spoken.recoveryEndWorkout].exists)
        XCTAssertFalse(alert.buttons[Spoken.recoveryDiscard].exists)

        app.resumeRecoveredWorkout()
        app.assertSetScreen(exercise: "Overhead Press", position: Spoken.overheadPosition)
    }

    @MainActor
    func testEndWorkoutFromAlertShowsSummaryAndSave() {
        let app = launch(scenario: UITestingContract.Scenario.inProgress)
        let alert = assertRecoveryAlert(app)
        alert.buttons[Spoken.recoveryEndWorkout].tapSettled()
        XCTAssertTrue(alert.waitForNonExistence(), "the alert didn't close")

        app.assertSummary(title: Spoken.workoutEnded)
        XCTAssertTrue(app.summaryLayer.staticTexts[Spoken.setsCompleted(1)].exists)
        app.summaryLayer.buttons["Save"].tapSettled()
        app.assertNoSessionLayer()
        // A recovered session has no pushed detail screen under the cover: the list itself is showing.
        app.assertRow(longRests, valueContains: Spoken.lastDone)
    }

    @MainActor
    func testNothingDoneOffersDiscardAndLeavesNoTrace() {
        let app = launch(scenario: UITestingContract.Scenario.nothingDone)
        let alert = assertRecoveryAlert(app)
        XCTAssertTrue(alert.buttons[Spoken.resume].exists)
        XCTAssertTrue(alert.buttons[Spoken.recoveryDiscard].exists)
        XCTAssertFalse(alert.buttons[Spoken.recoveryEndWorkout].exists)

        alert.buttons[Spoken.recoveryDiscard].tapSettled()
        XCTAssertTrue(alert.waitForNonExistence(), "the alert didn't close")
        app.assertNoSessionLayer()
        app.assertRow(longRests, valueContains: Spoken.notDoneYet)
    }

    @MainActor
    func testFinishedWorkoutOpensSummaryWithoutAlert() {
        let app = launch(scenario: UITestingContract.Scenario.onSummary)
        app.assertSummary(title: Spoken.workoutComplete)
        XCTAssertEqual(app.summaryVolume.value as? String, Spoken.plannedVolume)
        XCTAssertFalse(app.alerts.firstMatch.exists, "an alert showed over the summary")
    }

    /// Starts "Long Rests" on the disk store, does the first set, and kills the app on the rest screen.
    /// Relaunches with the same store and returns the app showing the recovery alert, and when Done was tapped.
    @MainActor
    private func killDuringRestAndRelaunch() -> (app: XCUIApplication, doneTappedAt: Date) {
        let first = launch(scenario: UITestingContract.Scenario.templates, store: UITestingContract.Store.disk)
        first.startWorkout(named: longRests)
        first.assertSetScreen(exercise: "Bench Press", position: Spoken.benchSet1Position)
        // A tap while the full-screen cover is still settling can reach the app and do nothing.
        let done = first.setScreen.buttons[ID.setDone]
        XCTAssertTrue(done.waitUntilSettled(), "Done never settled")
        let doneTappedAt = Date()
        done.tap()
        first.assertRestScreen()
        first.terminate()

        // `templates` with keep data seeds nothing (the disk store is kept); the scenario name is only required.
        let app = launch(
            scenario: UITestingContract.Scenario.templates, store: UITestingContract.Store.disk, keepData: true)
        assertRecoveryAlert(app)
        return (app, doneTappedAt)
    }

    /// The rest is still running: the "Up next" line is right, the countdown is no more than what is left of
    /// 600 s since Done (so Resume didn't restart it) and it keeps changing.
    @MainActor
    private func assertRestStillCountingDown(_ app: XCUIApplication, doneTappedAt: Date) {
        app.assertRestScreen()
        let upNext = app.restScreen.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", Spoken.upNextLabel)).firstMatch
        XCTAssertTrue(upNext.waitForExistence(timeout: defaultTimeout), "no Up next")
        XCTAssertEqual(upNext.value as? String, Spoken.longRestsUpNextSet2)
        guard let remaining = remainingSeconds(app) else { return XCTFail("no readable countdown") }
        let elapsed = Int(Date().timeIntervalSince(doneTappedAt))
        XCTAssertTrue(
            (300...(600 - elapsed + 2)).contains(remaining),
            "remaining \(remaining) s after \(elapsed) s since Done isn't a running countdown")
        // It keeps counting down: the label changes within a few seconds.
        let ring = app.restScreen.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", Spoken.restRemainingLabel)).firstMatch
        let before = ring.label
        XCTAssertTrue(ring.waitUntil("label != '\(before)'", timeout: 5 + 3), "the countdown didn't change from \(before)")
    }

    @MainActor
    func testKillDuringRestThenResumeKeepsCountingDown() {
        let (app, doneTappedAt) = killDuringRestAndRelaunch()
        app.resumeRecoveredWorkout()
        assertRestStillCountingDown(app, doneTappedAt: doneTappedAt)
    }

    @MainActor
    func testKillDuringRestThenEndWorkoutShowsOneSetCompleted() {
        let (app, _) = killDuringRestAndRelaunch()
        let alert = app.alerts[Spoken.recoveryTitle]
        alert.buttons[Spoken.recoveryEndWorkout].tapSettled()
        XCTAssertTrue(alert.waitForNonExistence(), "the alert didn't close")
        app.assertSummary(title: Spoken.workoutEnded)
        XCTAssertTrue(app.summaryLayer.staticTexts[Spoken.setsCompleted(1)].exists)
        app.summaryLayer.buttons["Save"].tapSettled()
        app.assertNoSessionLayer()
        app.assertRow(longRests, valueContains: Spoken.lastDone)
        // One row only: the relaunch didn't seed the templates a second time.
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", longRests)).count, 1)
    }
}
