import Foundation
import Testing
@testable import WorkoutBuddy

struct SessionStatsTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func entry(
        _ status: SetStatus, reps: Int? = nil, kg: Double? = nil, planned: SetValues = SetValues(reps: 10, kg: 60, restSeconds: 90)
    ) -> SessionSnapshot.Entry {
        SessionSnapshot.Entry(
            id: UUID(), exerciseIndex: 0, setIndex: 0, exerciseID: UUID(), planned: planned,
            actualReps: reps, actualKg: kg, status: status, completedAt: nil)
    }

    private func snapshot(
        _ entries: [SessionSnapshot.Entry], endedAt: Date? = nil, pausedDuration: TimeInterval = 0, pausedAt: Date? = nil
    ) -> SessionSnapshot {
        SessionSnapshot(
            startedAt: t0, endedAt: endedAt, pausedDuration: pausedDuration, pausedAt: pausedAt,
            exerciseCount: 1, entries: entries)
    }

    @Test func countsEachStatus() {
        let stats = SessionStats(
            snapshot([entry(.done, reps: 10, kg: 60), entry(.done, reps: 8, kg: 60), entry(.skipped), entry(.notPerformed),
                      entry(.notPerformed), entry(.notPerformed), entry(.pending)]),
            now: at(0))
        #expect(stats.doneCount == 2)
        #expect(stats.skippedCount == 1)
        #expect(stats.notPerformedCount == 3)
    }

    @Test func volumeSumsActualRepsTimesKg() {
        // 10 x 60 + 8 x 62.5 = 600 + 500
        let stats = SessionStats(snapshot([entry(.done, reps: 10, kg: 60), entry(.done, reps: 8, kg: 62.5)]), now: at(0))
        #expect(stats.volume == 1100)
    }

    @Test func volumeUsesActualNotPlannedValues() {
        let stats = SessionStats(snapshot([entry(.done, reps: 12, kg: 50)]), now: at(0))
        #expect(stats.volume == 600)
    }

    @Test func bodyweightSetsAddZero() {
        let stats = SessionStats(snapshot([entry(.done, reps: 15, kg: 0), entry(.done, reps: 10, kg: 20)]), now: at(0))
        #expect(stats.volume == 200)
        let onlyBodyweight = SessionStats(snapshot([entry(.done, reps: 15, kg: 0)]), now: at(0))
        #expect(onlyBodyweight.volume == 0)
    }

    @Test func volumeIgnoresSkippedNotPerformedAndPendingSets() {
        let stats = SessionStats(
            snapshot([entry(.done, reps: 10, kg: 60), entry(.skipped, reps: 10, kg: 60), entry(.notPerformed, reps: 10, kg: 60),
                      entry(.pending, reps: 10, kg: 60)]),
            now: at(0))
        #expect(stats.volume == 600)
    }

    @Test func doneSetWithoutActualValuesFallsBackToThePlan() {
        let stats = SessionStats(snapshot([entry(.done)]), now: at(0))
        #expect(stats.volume == 600)
    }

    @Test func durationIsFrozenAtEndedAtAndExcludesPauses() {
        let finished = snapshot([entry(.done, reps: 1, kg: 1)], endedAt: at(1000), pausedDuration: 200)
        #expect(SessionStats(finished, now: at(5000)).duration == 800)
    }

    @Test func durationOfARunningSessionFollowsNow() {
        #expect(SessionStats(snapshot([entry(.pending)]), now: at(90)).duration == 90)
    }

    @Test func endedEarlyWhenAnySetIsNotPerformed() {
        #expect(!SessionStats(snapshot([entry(.done, reps: 1, kg: 1), entry(.skipped)]), now: at(0)).endedEarly)
        #expect(SessionStats(snapshot([entry(.done, reps: 1, kg: 1), entry(.notPerformed)]), now: at(0)).endedEarly)
    }

    @Test func canSaveNeedsADoneSet() {
        #expect(SessionStats(snapshot([entry(.done, reps: 1, kg: 1), entry(.skipped)]), now: at(0)).canSave)
        #expect(!SessionStats(snapshot([entry(.skipped), entry(.skipped)]), now: at(0)).canSave)
        #expect(!SessionStats(snapshot([entry(.skipped), entry(.notPerformed)]), now: at(0)).canSave)
        #expect(!SessionStats(snapshot([]), now: at(0)).canSave)
    }
}
