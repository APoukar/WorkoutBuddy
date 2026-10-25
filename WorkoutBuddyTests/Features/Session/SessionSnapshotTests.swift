import Foundation
import Testing
@testable import WorkoutBuddy

struct SessionSnapshotTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    /// Two exercises: 2 sets then 1 set. Planned 10 x 60 kg, 90 s rest.
    private func makeSnapshot(
        statuses: [SetStatus] = [.pending, .pending, .pending],
        endedAt: Date? = nil,
        pausedDuration: TimeInterval = 0,
        pausedAt: Date? = nil,
        restEndsAt: Date? = nil,
        lastActionAt: Date? = nil,
        completedAt: [Date?] = [nil, nil, nil]
    ) -> SessionSnapshot {
        let layout = [(0, 0), (0, 1), (1, 0)]
        let entries = zip(layout.indices, layout).map { index, position in
            SessionSnapshot.Entry(
                id: UUID(), exerciseIndex: position.0, setIndex: position.1, exerciseID: UUID(),
                planned: SetValues(reps: 10, kg: 60, restSeconds: 90),
                actualReps: nil, actualKg: nil, status: statuses[index], completedAt: completedAt[index])
        }
        return SessionSnapshot(
            startedAt: t0, endedAt: endedAt, pausedDuration: pausedDuration, pausedAt: pausedAt,
            restEndsAt: restEndsAt, lastActionAt: lastActionAt, exerciseCount: 2, entries: entries)
    }

    // MARK: Structure

    @Test func setCountIsPerExercise() {
        let snapshot = makeSnapshot()
        #expect(snapshot.setCount(ofExercise: 0) == 2)
        #expect(snapshot.setCount(ofExercise: 1) == 1)
        #expect(snapshot.setCount(ofExercise: 2) == 0)
    }

    // MARK: Elapsed

    @Test func elapsedRunsFromStart() {
        let snapshot = makeSnapshot()
        #expect(snapshot.elapsed(now: at(0)) == 0)
        #expect(snapshot.elapsed(now: at(125)) == 125)
    }

    @Test func elapsedIsFrozenWhilePaused() {
        let snapshot = makeSnapshot(pausedAt: at(100))
        #expect(snapshot.elapsed(now: at(100)) == 100)
        #expect(snapshot.elapsed(now: at(500)) == 100)
    }

    @Test func elapsedExcludesPausedDurationAfterResume() {
        let snapshot = makeSnapshot(pausedDuration: 40)
        #expect(snapshot.elapsed(now: at(200)) == 160)
    }

    @Test func elapsedExcludesEarlierPausesWhilePausedAgain() {
        let snapshot = makeSnapshot(pausedDuration: 40, pausedAt: at(100))
        #expect(snapshot.elapsed(now: at(900)) == 60)
    }

    @Test func elapsedIsFrozenAtEndedAt() {
        let snapshot = makeSnapshot(endedAt: at(300))
        #expect(snapshot.elapsed(now: at(300)) == 300)
        #expect(snapshot.elapsed(now: at(9_000)) == 300)
    }

    @Test func elapsedIgnoresALeftOverPauseOnceFinished() {
        let snapshot = makeSnapshot(endedAt: at(300), pausedAt: at(100))
        #expect(snapshot.elapsed(now: at(9_000)) == 300)
    }

    @Test func elapsedIsNeverNegative() {
        // Now before the start (clock change) and a pause longer than the time elapsed.
        #expect(makeSnapshot().elapsed(now: at(-50)) == 0)
        #expect(makeSnapshot(pausedDuration: 500).elapsed(now: at(100)) == 0)
    }

    // MARK: Paused and finished

    @Test func isPausedOnlyWhilePausedAndNotFinished() {
        #expect(!makeSnapshot().isPaused)
        #expect(makeSnapshot(pausedAt: at(10)).isPaused)
        #expect(!makeSnapshot(endedAt: at(20), pausedAt: at(10)).isPaused)
    }

    @Test func isFinishedFollowsEndedAt() {
        #expect(!makeSnapshot().isFinished)
        #expect(makeSnapshot(endedAt: at(20)).isFinished)
    }

    @Test func hasDoneSetIgnoresSkippedAndNotPerformed() {
        #expect(!makeSnapshot().hasDoneSet)
        #expect(!makeSnapshot(statuses: [.skipped, .notPerformed, .pending]).hasDoneSet)
        #expect(makeSnapshot(statuses: [.skipped, .done, .pending]).hasDoneSet)
    }

    // MARK: Current set

    @Test func currentSetIsTheFirstPendingOne() {
        #expect(makeSnapshot().currentSetIndex == 0)
        #expect(makeSnapshot(statuses: [.done, .skipped, .pending]).currentSetIndex == 2)
        #expect(makeSnapshot(statuses: [.done, .pending, .pending]).currentSetIndex == 1)
        #expect(makeSnapshot(statuses: [.done, .done, .done]).currentSetIndex == nil)
    }

    // MARK: Rest remaining

    @Test func restRemainingRoundsUp() {
        let snapshot = makeSnapshot(statuses: [.done, .pending, .pending], restEndsAt: at(100))
        #expect(snapshot.restRemaining(now: at(10.8)) == 90)  // 89.2 s left
        #expect(snapshot.restRemaining(now: at(10)) == 90)
        #expect(snapshot.restRemaining(now: at(99.5)) == 1)
        #expect(snapshot.restRemaining(now: at(99.99)) == 1)
    }

    @Test func restRemainingIsNilAtAndAfterTheEnd() {
        let snapshot = makeSnapshot(statuses: [.done, .pending, .pending], restEndsAt: at(100))
        #expect(snapshot.restRemaining(now: at(100)) == nil)
        #expect(snapshot.restRemaining(now: at(250)) == nil)
    }

    @Test func expiredRestIsOneThatRanOutAndWasNotCleared() {
        let snapshot = makeSnapshot(statuses: [.done, .pending, .pending], restEndsAt: at(100))
        #expect(!snapshot.hasExpiredRest(now: at(99)))
        #expect(snapshot.hasExpiredRest(now: at(100)))
        #expect(snapshot.hasExpiredRest(now: at(500)))
        #expect(!makeSnapshot().hasExpiredRest(now: at(500)))
    }

    @Test func autoAdvanceDeadlineIsTheRunningRestsEnd() {
        let snapshot = makeSnapshot(statuses: [.done, .pending, .pending], restEndsAt: at(100))
        #expect(snapshot.autoAdvanceDeadline == at(100))
        // Still returned once it has run out but wasn't cleared: it doesn't depend on the time.
        #expect(makeSnapshot(statuses: [.done, .pending, .pending], restEndsAt: at(-5)).autoAdvanceDeadline == at(-5))
    }

    @Test func autoAdvanceDeadlineIsNilWhilePausedFinishedOrWithoutARest() {
        let paused = makeSnapshot(statuses: [.done, .pending, .pending], pausedAt: at(50), restEndsAt: at(100))
        #expect(paused.autoAdvanceDeadline == nil)
        let finished = makeSnapshot(statuses: [.done, .done, .done], endedAt: at(60), restEndsAt: at(100))
        #expect(finished.autoAdvanceDeadline == nil)
        #expect(makeSnapshot().autoAdvanceDeadline == nil)
    }

    @Test func expiredRestIsFrozenWhilePausedAndIgnoredOnceFinished() {
        let paused = makeSnapshot(statuses: [.done, .pending, .pending], pausedAt: at(50), restEndsAt: at(100))
        #expect(!paused.hasExpiredRest(now: at(500)))
        let finished = makeSnapshot(statuses: [.done, .done, .done], endedAt: at(60), restEndsAt: at(40))
        #expect(!finished.hasExpiredRest(now: at(500)))
    }

    @Test func restRemainingIsNilWithoutARest() {
        #expect(makeSnapshot().restRemaining(now: at(10)) == nil)
    }

    @Test func restRemainingIsFrozenWhilePaused() {
        let snapshot = makeSnapshot(
            statuses: [.done, .pending, .pending], pausedAt: at(40), restEndsAt: at(100))
        #expect(snapshot.restRemaining(now: at(40)) == 60)
        #expect(snapshot.restRemaining(now: at(5_000)) == 60)
    }

    // MARK: Screen

    @Test func screenShowsTheFirstSetAtTheStart() {
        #expect(makeSnapshot().screen(now: at(5)) == .set(0))
    }

    @Test func screenShowsTheNextPendingSetAfterASkip() {
        let snapshot = makeSnapshot(statuses: [.skipped, .pending, .pending])
        #expect(snapshot.screen(now: at(5)) == .set(1))
    }

    @Test func screenShowsTheRestWithTheNextSet() {
        let snapshot = makeSnapshot(statuses: [.done, .pending, .pending], restEndsAt: at(100))
        #expect(snapshot.screen(now: at(20)) == .rest(next: 1, remaining: 80))
    }

    @Test func screenShowsTheRestAcrossExercises() {
        let snapshot = makeSnapshot(statuses: [.done, .done, .pending], restEndsAt: at(100))
        #expect(snapshot.screen(now: at(20)) == .rest(next: 2, remaining: 80))
    }

    @Test func screenShowsTheNextSetOnceTheRestExpired() {
        let snapshot = makeSnapshot(statuses: [.done, .pending, .pending], restEndsAt: at(100))
        #expect(snapshot.screen(now: at(100)) == .set(1))
        #expect(snapshot.screen(now: at(500)) == .set(1))
    }

    @Test func screenKeepsTheRestWhilePausedEvenLongAfterItsEnd() {
        let snapshot = makeSnapshot(
            statuses: [.done, .pending, .pending], pausedAt: at(40), restEndsAt: at(100))
        #expect(snapshot.screen(now: at(5_000)) == .rest(next: 1, remaining: 60))
    }

    @Test func screenShowsTheSummaryWhenTheLastSetIsDone() {
        let snapshot = makeSnapshot(statuses: [.done, .done, .done], endedAt: at(300))
        #expect(snapshot.screen(now: at(400)) == .summary)
    }

    @Test func screenShowsTheSummaryWhenEverySetWasSkipped() {
        let snapshot = makeSnapshot(statuses: [.skipped, .skipped, .skipped], endedAt: at(300))
        #expect(snapshot.screen(now: at(400)) == .summary)
    }

    @Test func screenShowsTheSummaryAfterEndingEarly() {
        let snapshot = makeSnapshot(statuses: [.done, .notPerformed, .notPerformed], endedAt: at(300))
        #expect(snapshot.screen(now: at(400)) == .summary)
    }

    @Test func screenShowsTheSummaryWhenFinishedEvenIfASetIsPending() {
        let snapshot = makeSnapshot(statuses: [.done, .pending, .pending], endedAt: at(300))
        #expect(snapshot.screen(now: at(400)) == .summary)
    }

    @Test func screenShowsTheSummaryWhenNoSetIsLeftEvenIfARestIsStored() {
        // Can't happen (finishing clears the rest), but the data must not trap the view.
        let snapshot = makeSnapshot(statuses: [.done, .done, .done], restEndsAt: at(500))
        #expect(snapshot.screen(now: at(100)) == .summary)
    }

    // MARK: Undo target

    @Test func undoTargetIsTheDoneSetBeforeTheCurrentOneWhileResting() {
        let first = makeSnapshot(statuses: [.done, .pending, .pending], restEndsAt: at(100))
        #expect(first.undoTargetIndex(now: at(20)) == 0)
        let later = makeSnapshot(statuses: [.done, .done, .pending], restEndsAt: at(100))
        #expect(later.undoTargetIndex(now: at(20)) == 1)
    }

    @Test func undoTargetIsNilAfterTheRestExpired() {
        let snapshot = makeSnapshot(statuses: [.done, .pending, .pending], restEndsAt: at(100))
        #expect(snapshot.undoTargetIndex(now: at(100)) == nil)
        #expect(snapshot.undoTargetIndex(now: at(300)) == nil)
    }

    @Test func undoTargetIsNilOnTheSetScreen() {
        #expect(makeSnapshot().undoTargetIndex(now: at(20)) == nil)
        #expect(makeSnapshot(statuses: [.done, .pending, .pending]).undoTargetIndex(now: at(20)) == nil)
    }

    @Test func undoTargetIsNilWhenThePreviousSetIsNotDone() {
        let snapshot = makeSnapshot(statuses: [.done, .skipped, .pending], restEndsAt: at(100))
        #expect(snapshot.undoTargetIndex(now: at(20)) == nil)
    }

    @Test func undoTargetIsNilOnceFinished() {
        let snapshot = makeSnapshot(
            statuses: [.done, .pending, .pending], endedAt: at(50), restEndsAt: at(100))
        #expect(snapshot.undoTargetIndex(now: at(60)) == nil)
    }

    // MARK: Prefill

    @Test func prefillUsesThePlan() {
        let prefill = makeSnapshot().prefill(forSetAt: 1)
        #expect(prefill.reps == 10)
        #expect(prefill.kg == 60)
    }

    @Test func prefillUsesActualValuesAfterAnUndo() {
        var snapshot = makeSnapshot()
        snapshot.entries[0].actualReps = 8
        snapshot.entries[0].actualKg = 62.5
        let prefill = snapshot.prefill(forSetAt: 0)
        #expect(prefill.reps == 8)
        #expect(prefill.kg == 62.5)
    }

    @Test func prefillMixesActualAndPlannedValues() {
        var snapshot = makeSnapshot()
        snapshot.entries[0].actualKg = 0
        let prefill = snapshot.prefill(forSetAt: 0)
        #expect(prefill.reps == 10)
        #expect(prefill.kg == 0)
    }

    // MARK: Last activity

    @Test func lastActivityIsTheStartWithoutAnyResolvedSet() {
        #expect(makeSnapshot().lastActivity == t0)
    }

    @Test func lastActivityIsTheLatestDoneOrSkippedCompletion() {
        let snapshot = makeSnapshot(
            statuses: [.done, .skipped, .pending], completedAt: [at(60), at(150), nil])
        #expect(snapshot.lastActivity == at(150))
    }

    @Test func lastActivityIgnoresPendingAndNotPerformedSets() {
        // A pending set with a stray timestamp (an Undo clears it, but be defensive) doesn't count.
        let snapshot = makeSnapshot(
            statuses: [.done, .pending, .notPerformed], completedAt: [at(60), at(400), at(500)])
        #expect(snapshot.lastActivity == at(60))
    }

    @Test func lastActivityIsThePauseTimeWhilePaused() {
        let snapshot = makeSnapshot(
            statuses: [.done, .pending, .pending], pausedAt: at(900), completedAt: [at(60), nil, nil])
        #expect(snapshot.lastActivity == at(900))
    }

    @Test func lastActivityIsTheLastActionWhenLaterThanEveryResolvedSet() {
        // Done at +60, then paused and resumed at +1800: the resume is the last activity.
        let snapshot = makeSnapshot(
            statuses: [.done, .pending, .pending], lastActionAt: at(1800), completedAt: [at(60), nil, nil])
        #expect(snapshot.lastActivity == at(1800))
    }

    @Test func lastActivityIsTheResolvedSetWhenLaterThanTheLastAction() {
        let snapshot = makeSnapshot(
            statuses: [.done, .skipped, .pending], lastActionAt: at(60), completedAt: [at(30), at(120), nil])
        #expect(snapshot.lastActivity == at(120))
    }

    @Test func lastActivityIsTheLastActionWithoutAnyResolvedSet() {
        #expect(makeSnapshot(lastActionAt: at(45)).lastActivity == at(45))
    }

    @Test func lastActivityIsNeverBeforeTheStart() {
        #expect(makeSnapshot(lastActionAt: at(-10)).lastActivity == t0)
    }

    @Test func lastActivityIsThePauseTimeEvenWhenTheLastActionIsLater() {
        let snapshot = makeSnapshot(
            statuses: [.done, .pending, .pending], pausedAt: at(900), lastActionAt: at(950), completedAt: [at(60), nil, nil])
        #expect(snapshot.lastActivity == at(900))
    }
}
