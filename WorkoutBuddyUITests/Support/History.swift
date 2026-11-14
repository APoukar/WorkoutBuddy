import XCTest

/// The History tab: the calendar's day cells, month navigation and the session detail's delete. XCUITest sees
/// `UICalendarView` day cells as buttons labelled "Saturday, November 14" (with a "Today, " prefix for today);
/// a day without a workout is disabled (today is always enabled by design); the dot is the cell's
/// `circlebadge.fill` image. Swiping between months is unreliable, so the month changes through the calendar's
/// own Previous Month button.
extension XCUIApplication {
    private typealias History = UITestingContract.History

    func openHistoryTab() {
        tabBars.buttons[History.tabLabel].tapSettled()
        XCTAssertTrue(navigationBars[History.tabLabel].waitForExistence(timeout: defaultTimeout), "no History screen")
    }

    /// The calendar's cell for the day. The label may carry the "Today, " prefix, so it is matched by its end.
    func dayCell(_ date: Date) -> XCUIElement {
        collectionViews.buttons.matching(
            NSPredicate(format: "label ENDSWITH %@", History.dayTitle(date))
        ).firstMatch
    }

    /// Waits until the day's cell exists and is (or is not) enabled.
    func waitForDayCell(
        _ date: Date, enabled: Bool, file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        let cell = dayCell(date)
        XCTAssertTrue(cell.waitForExistence(timeout: defaultTimeout), "no cell for \(date)", file: file, line: line)
        XCTAssertTrue(cell.waitUntilEnabled(enabled), "cell isEnabled != \(enabled): \(cell)", file: file, line: line)
        return cell
    }

    /// Taps Previous Month and waits until the month button shows the month of `date`.
    func goToPreviousMonth(showing date: Date, file: StaticString = #filePath, line: UInt = #line) {
        buttons[History.previousMonthIdentifier].tapSettled()
        let month = buttons[History.monthButtonLabel]
        XCTAssertTrue(
            month.waitUntil(NSPredicate(format: "value == %@", History.monthValue(date))),
            "the month is \(String(describing: month.value))", file: file, line: line)
    }

    /// The detail's title is the workout name.
    func assertDetail(
        workout: String = UITestingContract.Workout.longRests, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(
            navigationBars[workout].waitForExistence(timeout: defaultTimeout), "no detail for \(workout)",
            file: file, line: line)
    }

    /// The detail's Volume row: label "Volume", value like "1,420 kilograms".
    var detailVolume: XCUIElement {
        otherElements.matching(NSPredicate(format: "label == %@", UITestingContract.Spoken.volumeLabel)).firstMatch
    }

    /// One set row of the detail, read the way VoiceOver does. The list builds its rows lazily, so the list is
    /// scrolled (by swipes, which work here) until the row exists.
    func detailSetRow(
        _ spoken: String, file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        let row = otherElements[spoken]
        for _ in 0..<5 where !row.exists {
            collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: defaultTimeout), "no set row \(spoken)", file: file, line: line)
        return row
    }

    /// Delete toolbar button → the alert naming the day → Delete. Returns after the alert closed.
    func deleteSessionFromDetail(day: Date, file: StaticString = #filePath, line: UInt = #line) {
        buttons[UITestingContract.Identifier.historyDeleteSession].tapSettled()
        let alert = alerts[History.deleteAlertTitle]
        XCTAssertTrue(alert.waitForExistence(timeout: defaultTimeout), "no delete alert", file: file, line: line)
        XCTAssertTrue(
            alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", History.dayTitle(day))).firstMatch
                .exists,
            "the alert doesn't name the day", file: file, line: line)
        alert.buttons[History.deleteButton].tapSettled()
        XCTAssertTrue(alert.waitForNonExistence(), "the delete alert didn't close", file: file, line: line)
    }

    /// The day list's rows (buttons whose label starts with the workout name and the start time).
    var dayListRows: XCUIElementQuery {
        collectionViews.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", History.dayRowPrefix))
    }
}

/// A test that depends on "today" would see a seeded session cross midnight right after launch (and the
/// `onSummary` session starts 10 minutes before launch), so it is skipped within 15 minutes of local midnight.
func skipNearMidnight(now: Date = .now, calendar: Calendar = .current) throws {
    let startOfDay = calendar.startOfDay(for: now)
    let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86_400)
    let margin: TimeInterval = 15 * 60
    try XCTSkipIf(
        now.timeIntervalSince(startOfDay) < margin || nextDay.timeIntervalSince(now) < margin,
        "within 15 minutes of midnight: the seeded sessions would sit on two days")
}
