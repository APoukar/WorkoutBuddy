import Foundation
import Testing
@testable import WorkoutBuddy

struct HistoryRulesTests {
    private static let prague: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }()
    private var cal: Calendar { Self.prague }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func entry(_ date: Date) -> HistoryEntry { HistoryEntry(id: UUID(), startedAt: date) }

    @Test func dayBoundaries() {
        #expect(HistoryDay(date(2026, 11, 14, 23, 59), calendar: cal) == HistoryDay(year: 2026, month: 11, day: 14))
        #expect(HistoryDay(date(2026, 11, 15, 0, 1), calendar: cal) == HistoryDay(year: 2026, month: 11, day: 15))
    }

    @Test func dayDependsOnTheCalendarTimeZone() {
        // 23:30 UTC on the 14th is 00:30 on the 15th in Prague.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let instant = utc.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 23, minute: 30))!
        #expect(HistoryDay(instant, calendar: utc) == HistoryDay(year: 2026, month: 11, day: 14))
        #expect(HistoryDay(instant, calendar: cal) == HistoryDay(year: 2026, month: 11, day: 15))
    }

    @Test func sessionCrossingMidnightSitsOnItsStartDay() {
        // The start decides; the end isn't part of the rules.
        let e = entry(date(2026, 11, 14, 23, 50))
        #expect(HistoryRules.days(of: [e], calendar: cal) == [HistoryDay(year: 2026, month: 11, day: 14)])
    }

    @Test func dstChangeDays() {
        // Spring forward 2026-03-29 (02:00 -> 03:00), fall back 2026-10-25 (03:00 -> 02:00).
        let spring = [entry(date(2026, 3, 29, 1, 30)), entry(date(2026, 3, 29, 3, 30)), entry(date(2026, 3, 29, 23, 59))]
        #expect(HistoryRules.days(of: spring, calendar: cal) == [HistoryDay(year: 2026, month: 3, day: 29)])
        let fallBack = [entry(date(2026, 10, 25, 0, 30)), entry(date(2026, 10, 25, 23, 59)), entry(date(2026, 10, 26, 0, 1))]
        #expect(
            HistoryRules.days(of: fallBack, calendar: cal)
                == [HistoryDay(year: 2026, month: 10, day: 25), HistoryDay(year: 2026, month: 10, day: 26)])
        // Both 02:30s of the repeated hour are the same day.
        let first = Date(timeIntervalSince1970: 1_792_888_200)  // 2026-10-25 00:30 UTC = 02:30 CEST
        let second = first + 3600  // 02:30 CET
        #expect(HistoryDay(first, calendar: cal) == HistoryDay(second, calendar: cal))
    }

    @Test func sessionsOfADayAreOldestFirst() {
        let late = entry(date(2026, 11, 14, 18))
        let early = entry(date(2026, 11, 14, 7))
        let other = entry(date(2026, 11, 13, 12))
        let day = HistoryDay(year: 2026, month: 11, day: 14)
        #expect(HistoryRules.sessions(on: day, in: [late, other, early], calendar: cal) == [early, late])
        #expect(HistoryRules.sessions(on: HistoryDay(year: 2026, month: 11, day: 1), in: [late], calendar: cal).isEmpty)
    }

    @Test func equalStartsAreDeterministic() {
        let at = date(2026, 11, 14, 9)
        let a = entry(at), b = entry(at)
        let day = HistoryDay(year: 2026, month: 11, day: 14)
        #expect(
            HistoryRules.sessions(on: day, in: [a, b], calendar: cal)
                == HistoryRules.sessions(on: day, in: [b, a], calendar: cal))
    }

    @Test func destinations() {
        let day = HistoryDay(year: 2026, month: 11, day: 14)
        let entries = (0..<3).map { entry(date(2026, 11, 14, 8 + $0)) }
        #expect(HistoryRules.destination(for: day, sessions: []) == .none)
        #expect(HistoryRules.destination(for: day, sessions: [entries[0]]) == .session(entries[0].id))
        #expect(HistoryRules.destination(for: day, sessions: entries) == .dayList(day))
    }

    @Test func pathAfterDeletingTheDetailOnly() {
        let a = entry(date(2026, 11, 14, 9))
        let path = HistoryRules.path(afterDeleting: a.id, from: [.session(a.id)], remaining: [], calendar: cal)
        #expect(path.isEmpty)
    }

    @Test func pathAfterDeletingOverADayListWithSessionsLeft() {
        let day = HistoryDay(year: 2026, month: 11, day: 14)
        let a = entry(date(2026, 11, 14, 9)), b = entry(date(2026, 11, 14, 17))
        let path = HistoryRules.path(
            afterDeleting: a.id, from: [.day(day), .session(a.id)], remaining: [a, b], calendar: cal)
        #expect(path == [.day(day)])
    }

    @Test func pathAfterDeletingTheLastSessionOfADayDropsTheDayList() {
        let day = HistoryDay(year: 2026, month: 11, day: 14)
        let a = entry(date(2026, 11, 14, 9))
        let elsewhere = entry(date(2026, 11, 13, 9))
        let path = HistoryRules.path(
            afterDeleting: a.id, from: [.day(day), .session(a.id)], remaining: [a, elsewhere], calendar: cal)
        #expect(path.isEmpty)
    }

    @Test func pathWithoutTheSessionIsUnchanged() {
        let day = HistoryDay(year: 2026, month: 11, day: 14)
        let path: [HistoryRoute] = [.day(day)]
        #expect(HistoryRules.path(afterDeleting: UUID(), from: path, remaining: [], calendar: cal) == path)
    }

    @Test func todayIsSelectableEvenWithoutAWorkout() {
        let d1 = HistoryDay(year: 2026, month: 11, day: 10)
        let today = HistoryDay(year: 2026, month: 11, day: 14)
        let other = HistoryDay(year: 2026, month: 11, day: 12)
        #expect(HistoryRules.isSelectable(d1, days: [d1], today: today))
        #expect(HistoryRules.isSelectable(today, days: [d1], today: today))
        #expect(HistoryRules.isSelectable(today, days: [], today: today))
        #expect(!HistoryRules.isSelectable(other, days: [d1], today: today))
    }

    @Test func daysToReloadIsTheSymmetricDifference() {
        let d1 = HistoryDay(year: 2026, month: 11, day: 1)
        let d2 = HistoryDay(year: 2026, month: 11, day: 2)
        let d3 = HistoryDay(year: 2026, month: 10, day: 30)
        #expect(HistoryRules.daysToReload(old: [d1, d2], new: [d2, d3]) == [d3, d1])
        #expect(HistoryRules.daysToReload(old: [d1], new: [d1]).isEmpty)
        #expect(HistoryRules.daysToReload(old: [], new: [d2]) == [d2])
    }

    @Test func rangeEndIsTheStartOfToday() {
        let end = HistoryRules.availableRangeEnd(now: date(2026, 11, 14, 15, 20), calendar: cal)
        #expect(end == date(2026, 11, 14))
    }

    @Test func rangeEndOnTheLastDayOfAMonthStaysInThatMonth() {
        let end = HistoryRules.availableRangeEnd(now: date(2026, 10, 31, 23, 59), calendar: cal)
        #expect(HistoryDay(end, calendar: cal) == HistoryDay(year: 2026, month: 10, day: 31))
    }

    @Test func dayConvertsToDateComponents() {
        let day = HistoryDay(year: 2026, month: 11, day: 14)
        let parts = day.dateComponents(calendar: cal)
        #expect(parts.year == 2026 && parts.month == 11 && parts.day == 14)
        #expect(HistoryDay(parts) == day)
        #expect(HistoryDay(DateComponents(year: 2026)) == nil)
    }
}
