import XCTest

/// The session layers, found by their container identifiers. Every query goes through a layer, never
/// through `app`: during a review and under the paused overlay the screen underneath stays in XCUITest's
/// element tree (hidden from VoiceOver, but still there), so `app.buttons["Done"]` could find the wrong one.
extension XCUIApplication {
    func layer(_ identifier: String) -> XCUIElement {
        descendants(matching: .any)[identifier]
    }

    var setScreen: XCUIElement { layer(UITestingContract.Identifier.setScreen) }
    var restScreen: XCUIElement { layer(UITestingContract.Identifier.restScreen) }
    var reviewLayer: XCUIElement { layer(UITestingContract.Identifier.review) }
    var pausedLayer: XCUIElement { layer(UITestingContract.Identifier.paused) }
    var summaryLayer: XCUIElement { layer(UITestingContract.Identifier.summary) }

    /// The summary's Volume element (label "Volume", value like "1,420 kilograms").
    var summaryVolume: XCUIElement {
        summaryLayer.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", UITestingContract.Spoken.volumeLabel)).firstMatch
    }

    /// Pause from the given screen (set or rest), check the paused layer offers Resume and End Workout, then
    /// Resume and wait until the layer is gone.
    func pauseAndResume(from screen: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        screen.buttons["Pause"].tap()
        XCTAssertTrue(pausedLayer.waitForExistence(timeout: defaultTimeout), "no paused overlay", file: file, line: line)
        XCTAssertTrue(pausedLayer.buttons["Resume"].exists, "no Resume", file: file, line: line)
        XCTAssertTrue(
            pausedLayer.buttons[UITestingContract.Identifier.pausedEndWorkout].exists, "no End Workout",
            file: file, line: line)
        pausedLayer.buttons["Resume"].tap()
        XCTAssertTrue(pausedLayer.waitForNonExistence(), "the paused overlay didn't close", file: file, line: line)
    }

    /// Pause from the set or rest screen and tap End Workout (which opens the confirmation).
    func pauseAndTapEndWorkout(from screen: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        screen.buttons["Pause"].tap()
        XCTAssertTrue(pausedLayer.waitForExistence(timeout: defaultTimeout), "no paused overlay", file: file, line: line)
        pausedLayer.buttons[UITestingContract.Identifier.pausedEndWorkout].tap()
    }

    /// Waits until none of the session layers exists: the session cover has closed.
    func assertNoSessionLayer(file: StaticString = #filePath, line: UInt = #line) {
        for layer in [setScreen, restScreen, reviewLayer, pausedLayer, summaryLayer] {
            XCTAssertTrue(
                layer.waitForNonExistence(), "a session layer is still showing: \(layer)", file: file, line: line)
        }
    }

    /// After the session cover closes the workout's detail is still pushed: go back to the list and check the
    /// workout's row value contains `text`.
    func assertRowAfterSession(
        _ workout: String, valueContains text: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        goBack(from: workout)
        assertRow(workout, valueContains: text, file: file, line: line)
    }

    /// Looks up the workout's row in the Workouts list and waits until its value contains `text`.
    func assertRow(
        _ workout: String, valueContains text: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let row = buttons[workout]
        XCTAssertTrue(row.waitForExistence(timeout: defaultTimeout), "no row for \(workout)", file: file, line: line)
        XCTAssertTrue(
            row.waitUntil("value CONTAINS '\(text)'"), "row value: \(String(describing: row.value))",
            file: file, line: line)
    }

    /// Answers the launch recovery alert (the `inProgress` and `nothingDone` scenarios raise it) with Resume.
    func resumeRecoveredWorkout(file: StaticString = #filePath, line: UInt = #line) {
        let resume = alerts.buttons[UITestingContract.Spoken.resume]
        XCTAssertTrue(resume.waitForExistence(timeout: defaultTimeout), "no recovery alert", file: file, line: line)
        XCTAssertTrue(resume.waitUntilSettled(), "the recovery alert never settled", file: file, line: line)
        resume.tap()
        XCTAssertTrue(resume.waitForNonExistence(), "the recovery alert didn't close", file: file, line: line)
    }

    /// Taps Start Workout on the open template and waits for the first set screen.
    func startWorkout(named name: String) {
        buttons[name].tap()
        let start = buttons["Start Workout"]
        XCTAssertTrue(start.waitForExistence(timeout: defaultTimeout), "Start Workout didn't appear")
        start.tap()
    }

    /// "On the set screen" means the set layer exists and neither the review nor the paused layer is above it.
    func assertSetScreen(
        exercise: String, position: String, timeout: TimeInterval = defaultTimeout,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(setScreen.waitForExistence(timeout: timeout), "no set screen", file: file, line: line)
        XCTAssertFalse(reviewLayer.exists, "a review covers the set screen", file: file, line: line)
        XCTAssertFalse(pausedLayer.exists, "the paused overlay covers the set screen", file: file, line: line)
        XCTAssertTrue(
            setScreen.staticTexts[exercise].waitForExistence(timeout: timeout),
            "set screen isn't showing \(exercise)", file: file, line: line)
        XCTAssertTrue(
            setScreen.staticTexts[position].waitForExistence(timeout: timeout),
            "set screen isn't at \(position)", file: file, line: line)
    }

    func assertRestScreen(
        timeout: TimeInterval = defaultTimeout, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(restScreen.waitForExistence(timeout: timeout), "no rest screen", file: file, line: line)
        XCTAssertFalse(pausedLayer.exists, "the paused overlay covers the rest screen", file: file, line: line)
        XCTAssertTrue(restScreen.buttons["Skip Rest"].exists, "rest screen has no Skip Rest", file: file, line: line)
    }

    func assertSummary(
        title: String, timeout: TimeInterval = defaultTimeout, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(summaryLayer.waitForExistence(timeout: timeout), "no summary", file: file, line: line)
        XCTAssertFalse(reviewLayer.exists, "a review covers the summary", file: file, line: line)
        XCTAssertFalse(pausedLayer.exists, "the paused overlay covers the summary", file: file, line: line)
        XCTAssertTrue(
            summaryLayer.staticTexts[title].waitForExistence(timeout: timeout),
            "summary title isn't \(title)", file: file, line: line)
    }

    /// The review shows its status badge ("Done" or "Skipped") and sits above the set screen or summary.
    func assertReview(
        status: String, timeout: TimeInterval = defaultTimeout, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(reviewLayer.waitForExistence(timeout: timeout), "no review", file: file, line: line)
        XCTAssertFalse(pausedLayer.exists, "the paused overlay covers the review", file: file, line: line)
        XCTAssertTrue(
            reviewLayer.staticTexts[status].waitForExistence(timeout: timeout),
            "review status isn't \(status)", file: file, line: line)
    }
}
