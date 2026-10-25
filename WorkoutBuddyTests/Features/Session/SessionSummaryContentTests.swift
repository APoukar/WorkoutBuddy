import Foundation
import Testing
@testable import WorkoutBuddy

struct SessionSummaryContentTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func content(
        _ statuses: [SetStatus], kg: Double = 60, duration: TimeInterval = 3_900, locale: Locale = Locale(identifier: "en_US")
    ) -> SessionSummaryContent {
        let entries = statuses.enumerated().map { index, status in
            SessionSnapshot.Entry(
                id: UUID(), exerciseIndex: 0, setIndex: index, exerciseID: UUID(),
                planned: SetValues(reps: 10, kg: kg, restSeconds: 90),
                actualReps: status == .done ? 10 : nil, actualKg: status == .done ? kg : nil,
                status: status, completedAt: nil)
        }
        let snapshot = SessionSnapshot(
            startedAt: t0, endedAt: t0 + duration, exerciseCount: 1, entries: entries)
        return SessionSummaryContent(SessionStats(snapshot, now: t0 + duration), locale: locale)
    }

    @Test func completedWorkout() {
        let content = content([.done, .done, .skipped], kg: 62.5)
        #expect(content.title == "Workout Complete")
        #expect(content.durationText == "1 hr, 5 min")
        #expect(content.spokenDurationText == "1 hour, 5 minutes")
        #expect(content.volumeText == "1,250\u{00A0}kg")
        #expect(content.spokenVolumeText == "1,250 kilograms")
        #expect(content.counts.map(\.text) == ["2 completed", "1 skipped"])
        #expect(content.canSave)
    }

    @Test func endedEarlyWorkout() {
        let content = content([.done, .notPerformed, .notPerformed])
        #expect(content.title == "Workout Ended")
        #expect(content.counts.map(\.text) == ["1 completed", "2 not performed"])
        #expect(content.counts.map(\.spokenText) == ["1 set completed", "2 sets not performed"])
        #expect(content.canSave)
    }

    @Test func pendingSetsOfAnEndedWorkoutShowAsNotPerformed() {
        let content = content([.done, .pending, .pending])
        #expect(content.title == "Workout Ended")
        #expect(content.counts.map(\.text) == ["1 completed", "2 not performed"])
        #expect(content.canSave)
    }

    @Test func workoutWithNoDoneSetCannotBeSaved() {
        let content = content([.skipped, .skipped], duration: 45)
        #expect(!content.canSave)
        #expect(content.title == "Workout Ended")
        #expect(content.durationText == "45 sec")
        #expect(content.volumeText == "0\u{00A0}kg")
        #expect(content.counts.map(\.text) == ["0 completed", "2 skipped"])
    }

    @Test func numbersFollowTheLocale() {
        let czech = Locale(identifier: "en_CZ")
        let content = content([.done, .done, .done], kg: 62.5, locale: czech)
        #expect(content.volumeText == Formatters.volume(1_875, locale: czech))
        #expect(content.volumeText != Formatters.volume(1_875, locale: Locale(identifier: "en_US")))
    }
}
