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
