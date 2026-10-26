import XCTest

/// Looking back at earlier sets (done or skipped), from the live set screen and from the summary. The
/// `inProgress` scenario has Bench Press set 1 done (10 x 60), set 2 skipped (8 x 62.5) and Overhead Press
/// (8 x 40) as the current set; it raises the recovery alert first, so each test taps Resume. Every wait is
/// an expectation, never a sleep.
nonisolated final class ReviewSetsUITests: XCTestCase {
    private typealias ID = UITestingContract.Identifier
    private typealias Spoken = UITestingContract.Spoken

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Helpers

    /// Launches `inProgress`, answers the recovery alert with Resume and checks the current set.
    @MainActor
    private func launchInProgress() -> XCUIApplication {
        let app = launch(scenario: UITestingContract.Scenario.inProgress)
        app.resumeRecoveredWorkout()
        assertCurrentSet(app)
        return app
    }

    @MainActor
    private func assertCurrentSet(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        app.assertSetScreen(exercise: "Overhead Press", position: Spoken.overheadPosition, file: file, line: line)
    }

    /// The review of this set: its status badge, exercise, position and the reps and kg it shows.
    @MainActor
    private func assertReview(
        _ app: XCUIApplication, status: String, exercise: String, position: String, reps: String, kg: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        app.assertReview(status: status, file: file, line: line)
        XCTAssertTrue(
            app.reviewLayer.staticTexts[exercise].waitForExistence(timeout: defaultTimeout),
            "review isn't of \(exercise)", file: file, line: line)
        XCTAssertTrue(
            app.reviewLayer.staticTexts[position].waitForExistence(timeout: defaultTimeout),
            "review isn't at \(position)", file: file, line: line)
        XCTAssertEqual(ValueControl(identifier: ID.repsControl, in: app.reviewLayer).value, reps, file: file, line: line)
        XCTAssertEqual(ValueControl(identifier: ID.kgControl, in: app.reviewLayer).value, kg, file: file, line: line)
    }

    /// The skipped second Bench Press set and the done first one, as the `inProgress` scenario has them.
    @MainActor
    private func assertSkippedSet2Review(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        assertReview(
            app, status: Spoken.statusSkipped, exercise: "Bench Press", position: Spoken.benchSet2Position,
            reps: "8", kg: "62.5 kilograms", file: file, line: line)
    }

    @MainActor
    private func assertDoneSet1Review(
        _ app: XCUIApplication, kg: String = "60 kilograms", file: StaticString = #filePath, line: UInt = #line
    ) {
        assertReview(
            app, status: Spoken.statusDone, exercise: "Bench Press", position: Spoken.benchSet1Position,
            reps: "10", kg: kg, file: file, line: line)
    }

    /// The buttons in the open review with this label (the layer under it is not searched).
    @MainActor
    private func reviewButtons(_ app: XCUIApplication, _ label: String) -> XCUIElementQuery {
        app.reviewLayer.buttons.matching(NSPredicate(format: "label == %@", label))
    }

    /// The top of the review's bottom bar: its highest button. The footer's Mark as Skipped lives in the
    /// scrolling content; on iPhone 17 at the default text size it starts below the screen and, scrolled a
    /// little, sits under the bar, where XCUITest still calls it hittable but the tap lands on the bar.
    @MainActor
    private func bottomBarTop(_ app: XCUIApplication) -> CGFloat {
        let barLabels = [
            Spoken.previousSet, Spoken.nextSet, Spoken.backToCurrentSet, Spoken.backToSummary, Spoken.markAsDone,
        ]
        let tops = barLabels.flatMap { label in
            reviewButtons(app, label).allElementsBoundByIndex.map { $0.frame.minY }
        }
        return tops.min() ?? app.windows.firstMatch.frame.maxY
    }

    /// Taps a button in the review. First it waits (2 s) for XCUITest to call the button hittable, so a tap doesn't
    /// land while the review is still sliding in. A content button (`inContent`, the footer's Mark as Skipped)
    /// is scrolled up until it is clear of the bottom bar, and no further; the drag starts in the left margin,
    /// above the bar (which doesn't scroll), where there's no control to catch it.
    ///
    /// On iOS 27 every button of a review opened from the summary is reported not hittable (hit point
    /// {-1, -1}, even the - / + buttons and Back), although a real touch reaches it: the coordinate taps below
    /// worked, so the underlying summary answers XCUITest's accessibility hit test but not touches. In that
    /// case the button is tapped by coordinate (the upper part of a content button, which is clear of the
    /// bar); the status or screen change that every caller checks afterwards proves the tap landed.
    @MainActor
    private func tapWhenHittable(
        _ app: XCUIApplication, _ button: XCUIElement, _ name: String, inContent: Bool = false,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(button.waitForExistence(timeout: defaultTimeout), "no \(name) button", file: file, line: line)
        func needsScrolling() -> Bool {
            inContent && button.frame.maxY > bottomBarTop(app)
        }
        for _ in 0..<6 where needsScrolling() {
            let content = app.reviewLayer.scrollViews.firstMatch
            let from = content.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.55))
            let to = content.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.15))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0)
        }
        XCTAssertFalse(needsScrolling(), "\(name) button is still out of reach", file: file, line: line)
        if !inContent, button.waitUntil("isHittable == true", timeout: 2) {
            button.tap()
        } else {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: inContent ? 0.25 : 0.5)).tap()
        }
    }

    /// Taps the review's only button with this label.
    @MainActor
    private func tapReviewButton(_ app: XCUIApplication, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let query = reviewButtons(app, label)
        XCTAssertEqual(query.count, 1, "expected one \(label) button in the review", file: file, line: line)
        tapWhenHittable(
            app, query.firstMatch, label, inContent: label == Spoken.markAsSkipped, file: file, line: line)
    }

    // MARK: Navigation

    /// Change the current set's reps, look back with swipes (skipped set, then done set) and forward again;
    /// the unsaved change survives. Then the same trip with the buttons: the set screen's Previous Set, the
    /// bottom bar's Previous / Next, and Back to Current Set. Swipes and buttons are one launch (the second
    /// trip starts where the first one ended, on the current set, whose reps are still 9).
    @MainActor
    func testSwipesAndButtonsLookBackAndForthKeepingUnsavedReps() {
        let app = launchInProgress()
        let reps = ValueControl(identifier: ID.repsControl, in: app.setScreen)
        XCTAssertEqual(reps.value, "8")
        reps.increment()
        XCTAssertEqual(reps.value, "9")

        // Swipes: right, right, left, left.
        app.swipeHorizontally(right: true)
        assertSkippedSet2Review(app)
        XCTAssertTrue(app.reviewLayer.buttons["Pause"].exists, "the review opened from the set screen has no Pause")
        app.swipeHorizontally(right: true)
        assertDoneSet1Review(app)
        app.swipeHorizontally(right: false)
        assertSkippedSet2Review(app)
        app.swipeHorizontally(right: false)
        XCTAssertTrue(app.reviewLayer.waitForNonExistence(), "the review stayed after swiping back")
        assertCurrentSet(app)
        XCTAssertEqual(ValueControl(identifier: ID.repsControl, in: app.setScreen).value, "9")

        // Buttons: Previous Set on the set screen, then the bar's Previous and Next.
        app.setScreen.buttons[Spoken.previousSet].tap()
        assertSkippedSet2Review(app)
        let previous = app.reviewLayer.buttons[Spoken.previousSet]
        XCTAssertTrue(previous.isEnabled)
        tapWhenHittable(app, previous, Spoken.previousSet)
        assertDoneSet1Review(app)
        // Set 1 is the oldest: there's nothing further back.
        XCTAssertFalse(app.reviewLayer.buttons[Spoken.previousSet].isEnabled, "Previous is enabled at the oldest set")
        tapReviewButton(app, Spoken.nextSet)
        assertSkippedSet2Review(app)

        // At the newest set both the bottom bar's Back button and the Next button are "Back to Current Set"
        // (Next acts as Back there). Both are tapped, one per trip; which one is which doesn't matter.
        let backButtons = reviewButtons(app, Spoken.backToCurrentSet)
        XCTAssertEqual(backButtons.count, 2, "expected the Back and Next buttons, both named Back to Current Set")
        tapWhenHittable(app, backButtons.element(boundBy: 1), "second Back to Current Set")
        XCTAssertTrue(app.reviewLayer.waitForNonExistence(), "the review stayed after the second Back button")
        assertCurrentSet(app)

        app.setScreen.buttons[Spoken.previousSet].tap()
        assertSkippedSet2Review(app)
        XCTAssertEqual(backButtons.count, 2)
        tapWhenHittable(app, backButtons.element(boundBy: 0), "first Back to Current Set")
        XCTAssertTrue(app.reviewLayer.waitForNonExistence(), "the review stayed after the first Back button")
        assertCurrentSet(app)
        XCTAssertEqual(ValueControl(identifier: ID.repsControl, in: app.setScreen).value, "9")
    }

    // MARK: Editing and marking

    /// Raise the done set's kg with +, go back, mark the skipped set as done and finish the workout: the
    /// summary shows 3 sets completed and a volume with both changes: 10 x 62.5 + 8 x 62.5 + 8 x 40 = 1,445.
    /// One launch for the kg correction and Mark as Done, because both only need the finished summary to prove.
    @MainActor
    func testCorrectingDoneSetAndMarkingSkippedSetAsDoneCountInTheSummary() {
        let app = launchInProgress()
        app.setScreen.buttons[Spoken.previousSet].tap()
        assertSkippedSet2Review(app)

        // Mark as Done on the skipped set: it becomes a done set (same values), and the button is replaced.
        tapReviewButton(app, Spoken.markAsDone)
        app.assertReview(status: Spoken.statusDone)
        XCTAssertEqual(reviewButtons(app, Spoken.markAsDone).count, 0, "Mark as Done is still offered")
        XCTAssertEqual(reviewButtons(app, Spoken.markAsSkipped).count, 1, "Mark as Skipped isn't offered")
        XCTAssertEqual(ValueControl(identifier: ID.kgControl, in: app.reviewLayer).value, "62.5 kilograms")

        // Correct the first set's kg: 60 + 2.5.
        tapReviewButton(app, Spoken.previousSet)
        assertDoneSet1Review(app)
        let kg = ValueControl(identifier: ID.kgControl, in: app.reviewLayer)
        kg.increment()
        XCTAssertEqual(kg.value, "62.5 kilograms")

        // Back to Current Set. The set 1 review has one Back button (Next is "Next Set" there).
        tapReviewButton(app, Spoken.backToCurrentSet)
        XCTAssertTrue(app.reviewLayer.waitForNonExistence(), "the review stayed after Back to Current Set")
        assertCurrentSet(app)

        app.setScreen.buttons[ID.setDone].tap()
        app.assertSummary(title: Spoken.workoutComplete)
        XCTAssertTrue(app.summaryLayer.staticTexts[Spoken.setsCompleted(3)].exists, "not 3 sets completed")
        XCTAssertEqual(app.summaryVolume.value as? String, Spoken.volumeAfterCorrectionAndMarkDone)
    }

    /// Mark as Skipped on the done first set: the review says "Skipped" and offers Mark as Done instead.
    /// Finishing the workout then counts only the Overhead Press set: 1 completed, 2 skipped (the first one and
    /// the second, which was skipped already), 320 kg. No set is "not performed", so the title stays "Workout Complete".
    @MainActor
    func testMarkingDoneSetAsSkippedChangesItsStatusAndTheSummary() {
        let app = launchInProgress()
        app.setScreen.buttons[Spoken.previousSet].tap()
        assertSkippedSet2Review(app)
        tapReviewButton(app, Spoken.previousSet)
        assertDoneSet1Review(app)

        tapReviewButton(app, Spoken.markAsSkipped)
        app.assertReview(status: Spoken.statusSkipped)
        XCTAssertEqual(reviewButtons(app, Spoken.markAsSkipped).count, 0, "Mark as Skipped is still offered")
        XCTAssertEqual(reviewButtons(app, Spoken.markAsDone).count, 1, "Mark as Done isn't offered")

        tapReviewButton(app, Spoken.backToCurrentSet)
        XCTAssertTrue(app.reviewLayer.waitForNonExistence(), "the review stayed after Back to Current Set")
        assertCurrentSet(app)
        app.setScreen.buttons[ID.setDone].tap()
        app.assertSummary(title: Spoken.workoutComplete)
        XCTAssertTrue(app.summaryLayer.staticTexts[Spoken.setsCompleted(1)].exists, "not 1 set completed")
        XCTAssertTrue(app.summaryLayer.staticTexts[Spoken.setsSkipped(2)].exists, "not 2 sets skipped")
        XCTAssertEqual(app.summaryVolume.value as? String, Spoken.volumeOfOverheadOnly)
    }

    // MARK: From the summary

    /// From the finished workout's summary: Review Sets opens the last set (no Pause, the time is frozen);
    /// Mark as Skipped on all three sets, walking back with Previous Set; Back to Summary then shows a
    /// workout that can't be saved: Discard Workout replaces Save.
    @MainActor
    func testReviewFromSummaryAndSkippingEverySetLeavesOnlyDiscard() {
        let app = launch(scenario: UITestingContract.Scenario.onSummary)
        app.assertSummary(title: Spoken.workoutComplete)
        XCTAssertTrue(app.summaryLayer.buttons["Save"].exists)
        // Review Sets is a list row below the counts and may be off screen (the list builds rows lazily).
        let reviewSets = app.summaryLayer.buttons[Spoken.reviewSets]
        for _ in 0..<4 where !(reviewSets.exists && reviewSets.isHittable) { app.summaryLayer.swipeUp() }
        XCTAssertTrue(reviewSets.isHittable, "Review Sets not reachable")
        reviewSets.tap()

        // The newest set, from the summary: Done, no Pause, and the way back is Back to Summary.
        assertReview(
            app, status: Spoken.statusDone, exercise: "Overhead Press", position: Spoken.overheadPosition,
            reps: "8", kg: "40 kilograms")
        XCTAssertFalse(app.reviewLayer.buttons["Pause"].exists, "the review from the summary offers Pause")
        XCTAssertGreaterThan(reviewButtons(app, Spoken.backToSummary).count, 0, "no Back to Summary")

        tapReviewButton(app, Spoken.markAsSkipped)
        app.assertReview(status: Spoken.statusSkipped)
        tapReviewButton(app, Spoken.previousSet)
        assertReview(
            app, status: Spoken.statusDone, exercise: "Bench Press", position: Spoken.benchSet2Position,
            reps: "8", kg: "62.5 kilograms")
        tapReviewButton(app, Spoken.markAsSkipped)
        app.assertReview(status: Spoken.statusSkipped)
        tapReviewButton(app, Spoken.previousSet)
        assertDoneSet1Review(app)
        tapReviewButton(app, Spoken.markAsSkipped)
        app.assertReview(status: Spoken.statusSkipped)

        // At set 1 only the bottom bar's button is named Back to Summary (Next is "Next Set").
        tapReviewButton(app, Spoken.backToSummary)
        XCTAssertTrue(app.reviewLayer.waitForNonExistence(), "the review stayed after Back to Summary")
        // The summary is still scrolled down from finding Review Sets: its title is above the visible part.
        let title = app.summaryLayer.staticTexts[Spoken.workoutEnded]
        for _ in 0..<4 where !title.exists {
            let from = app.summaryLayer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            let to = app.summaryLayer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0)
        }
        app.assertSummary(title: Spoken.workoutEnded)
        XCTAssertTrue(app.summaryLayer.staticTexts[Spoken.setsSkipped(3)].exists, "not 3 sets skipped")
        XCTAssertFalse(app.summaryLayer.buttons["Save"].exists, "Save is offered for a workout with no done set")
        XCTAssertTrue(app.summaryLayer.buttons[ID.summaryDiscardWorkout].exists, "no Discard Workout")
    }
}
