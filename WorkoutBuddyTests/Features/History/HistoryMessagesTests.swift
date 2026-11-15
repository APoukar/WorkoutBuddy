import Foundation
import Testing
@testable import WorkoutBuddy

struct HistoryMessagesTests {
    private let enUS = Locale(identifier: "en_US")
    private let enCZ = Locale(identifier: "en_CZ")
    private let prague = TimeZone(identifier: "Europe/Prague") ?? .gmt

    private var start: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = prague
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 18, minute: 30)) ?? .now
    }

    @Test func deleteMessageNamesTheDay() {
        #expect(HistoryMessages.deleteMessage(startedAt: start, locale: enUS, timeZone: prague)
            == "The workout from Saturday, November 14 will be removed from your history. This can't be undone.")
        #expect(HistoryMessages.deleteMessage(startedAt: start, locale: enCZ, timeZone: prague)
            == "The workout from Saturday 14 November will be removed from your history. This can't be undone.")
    }

    @Test func staticTexts() {
        #expect(HistoryMessages.deleteTitle == "Delete Workout?")
        #expect(HistoryMessages.emptyTitle == "No workouts yet")
        #expect(HistoryMessages.emptyMessage == "Saved workouts appear here.")
        #expect(HistoryMessages.notFoundTitle == "Workout Not Found")
    }

    @Test func plannedTexts() {
        let planned = SetValues(reps: 8, kg: 62.5, restSeconds: 90)
        #expect(HistoryMessages.plannedText(planned, locale: enUS) == "Planned 8 × 62.5\u{00A0}kg")
        #expect(HistoryMessages.spokenPlannedText(planned, locale: enUS) == "planned 8 reps at 62.5 kilograms")
        #expect(HistoryMessages.plannedText(planned, locale: Locale(identifier: "cs_CZ")) == "Planned 8 × 62,5\u{00A0}kg")
    }

    private func stats(duration: TimeInterval, paused: TimeInterval = 0) -> SessionStats {
        let snapshot = SessionSnapshot(
            startedAt: start, endedAt: start + duration, pausedDuration: paused, status: .completed,
            exerciseCount: 0, entries: [])
        return SessionStats(snapshot, now: start + duration)
    }

    @Test func dayRowTexts() {
        #expect(HistoryMessages.dayRowDetail(startedAt: start, stats: stats(duration: 3_900), locale: enCZ, timeZone: prague)
            == "18:30 · 1 hr, 5 min")
        #expect(HistoryMessages.spokenDayRow(
            name: "Push Day", startedAt: start, stats: stats(duration: 3_900), locale: enCZ, timeZone: prague)
            == "Push Day, 18:30, 1 hour, 5 minutes")
        #expect(HistoryMessages.spokenDayRow(
            name: nil, startedAt: start, stats: stats(duration: 45), locale: enCZ, timeZone: prague)
            == "Workout, 18:30, 45 seconds")
    }

    @Test func dayRowDurationExcludesPauses() {
        let stats = stats(duration: 4_200, paused: 300)
        #expect(HistoryMessages.dayRowDetail(startedAt: start, stats: stats, locale: enCZ, timeZone: prague)
            == "18:30 · 1 hr, 5 min")
    }

    @Test func workoutNameFallback() {
        #expect(HistoryMessages.workoutName("Legs") == "Legs")
        #expect(HistoryMessages.workoutName(nil) == "Workout")
    }
}
