import XCTest

/// F6: the History calendar, the day list, the session detail and deleting. Seeded by the `history` scenario:
/// two "Long Rests" sessions today (done as planned, 1,420 kg), and one on the 15th of the previous month
/// (ended early). Tests that depend on "today" are skipped within 15 minutes of midnight.
nonisolated final class HistoryUITests: XCTestCase {
    private typealias History = UITestingContract.History
    private typealias ID = UITestingContract.Identifier

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTodayOpensDayListThenDetail() throws {
        try skipNearMidnight()
        let app = launch(scenario: UITestingContract.Scenario.history)
        app.openHistoryTab()

        // Today has two sessions: the dot is there and a tap opens the day list, oldest first.
        let today = app.waitForDayCell(.now, enabled: true)
        XCTAssertTrue(today.images[History.dotIdentifier].waitForExistence(timeout: defaultTimeout), "no dot on today")
        today.tapSettled()
        XCTAssertTrue(
            app.navigationBars[History.dayTitle(.now)].waitForExistence(timeout: defaultTimeout), "no day list")
        XCTAssertTrue(app.dayListRows.element(boundBy: 1).waitForExistence(timeout: defaultTimeout), "no second row")
        XCTAssertEqual(app.dayListRows.count, 2)

        app.dayListRows.element(boundBy: 0).tapSettled()
        app.assertDetail()
        XCTAssertEqual(app.detailVolume.value as? String, UITestingContract.Spoken.plannedVolume)
        XCTAssertTrue(app.detailSetRow(History.setDoneAsPlanned).exists)
        XCTAssertFalse(app.staticTexts[History.endedEarly].exists, "a completed workout reads as ended early")
    }

    @MainActor
    func testPreviousMonthOpensEndedEarlyDetailDirectly() throws {
        try skipNearMidnight()
        let app = launch(scenario: UITestingContract.Scenario.history)
        app.openHistoryTab()
        let fifteenth = History.previousMonthFifteenth(now: .now)
        app.goToPreviousMonth(showing: fifteenth)

        // One session that day: the detail opens without a day list.
        let cell = app.waitForDayCell(fifteenth, enabled: true)
        XCTAssertTrue(cell.images[History.dotIdentifier].waitForExistence(timeout: defaultTimeout), "no dot on the 15th")
        cell.tapSettled()
        app.assertDetail()
        XCTAssertTrue(app.staticTexts[History.endedEarly].exists, "not marked as ended early")
        XCTAssertEqual(app.detailVolume.value as? String, History.volumeOfEndedEarlySession)
        // The changed kg shows its plan, the skipped and the never-reached sets are marked.
        XCTAssertTrue(app.detailSetRow(History.setChangedKg).exists)
        XCTAssertTrue(app.detailSetRow(History.setSkipped).exists)
        XCTAssertTrue(app.detailSetRow(History.setNotPerformed).exists)
    }

    @MainActor
    func testDeletingBothSessionsOfTodayRemovesRowsAndDot() throws {
        try skipNearMidnight()
        let app = launch(scenario: UITestingContract.Scenario.history)
        app.openHistoryTab()
        app.waitForDayCell(.now, enabled: true).tapSettled()
        XCTAssertTrue(app.dayListRows.element(boundBy: 1).waitForExistence(timeout: defaultTimeout), "no day list")

        // Deleting one of two pops back to the day list, which now has one row.
        app.dayListRows.element(boundBy: 0).tapSettled()
        app.assertDetail()
        app.deleteSessionFromDetail(day: .now)
        XCTAssertTrue(
            app.navigationBars[History.dayTitle(.now)].waitForExistence(timeout: defaultTimeout),
            "didn't return to the day list")
        XCTAssertTrue(app.dayListRows.element(boundBy: 1).waitForNonExistence(), "the deleted row is still there")
        XCTAssertEqual(app.dayListRows.count, 1)

        // Deleting the last one pops the (now empty) day list too. Today stays enabled by design, so the
        // dot is what shows the day is empty.
        app.dayListRows.element(boundBy: 0).tapSettled()
        app.assertDetail()
        app.deleteSessionFromDetail(day: .now)
        let today = app.waitForDayCell(.now, enabled: true)
        XCTAssertTrue(today.images[History.dotIdentifier].waitForNonExistence(), "today still has a dot")
    }

    @MainActor
    func testDeletingTheOnlySessionOfADayDisablesTheDay() throws {
        try skipNearMidnight()
        let app = launch(scenario: UITestingContract.Scenario.history)
        app.openHistoryTab()
        let fifteenth = History.previousMonthFifteenth(now: .now)
        app.goToPreviousMonth(showing: fifteenth)
        app.waitForDayCell(fifteenth, enabled: true).tapSettled()
        app.assertDetail()

        // Cancel keeps it; Delete pops straight back to the calendar.
        app.buttons[ID.historyDeleteSession].tapSettled()
        let alert = app.alerts[History.deleteAlertTitle]
        XCTAssertTrue(alert.waitForExistence(timeout: defaultTimeout), "no delete alert")
        alert.buttons["Cancel"].tapSettled()
        XCTAssertTrue(alert.waitForNonExistence(), "the alert didn't close")
        app.assertDetail()
        app.deleteSessionFromDetail(day: fifteenth)

        let cell = app.waitForDayCell(fifteenth, enabled: false)
        XCTAssertTrue(cell.images[History.dotIdentifier].waitForNonExistence(), "the emptied day still has a dot")
    }

    @MainActor
    func testSavedWorkoutAppearsOnToday() throws {
        try skipNearMidnight()
        let app = launch(scenario: UITestingContract.Scenario.onSummary)
        app.assertSummary(title: UITestingContract.Spoken.workoutComplete)
        app.summaryLayer.buttons["Save"].tapSettled()
        app.assertNoSessionLayer()

        app.openHistoryTab()
        let today = app.waitForDayCell(.now, enabled: true)
        XCTAssertTrue(today.images[History.dotIdentifier].waitForExistence(timeout: defaultTimeout), "no dot on today")
        // One session: the detail opens directly.
        today.tapSettled()
        app.assertDetail()
        XCTAssertEqual(app.detailVolume.value as? String, UITestingContract.Spoken.plannedVolume)
    }
}
