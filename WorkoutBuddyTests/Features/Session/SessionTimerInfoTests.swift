import Foundation
import Testing
@testable import WorkoutBuddy

struct SessionTimerInfoTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    // MARK: Elapsed

    @Test func elapsedIntervalStartsAfterThePausedTime() {
        let info = ElapsedTimerInfo(startedAt: t0, pausedDuration: 90, pausedAt: nil)
        #expect(info.interval.lowerBound == t0.addingTimeInterval(90))
        #expect(info.interval.upperBound == .distantFuture)
    }

    @Test func elapsedIntervalWithoutPauseStartsAtTheStart() {
        let info = ElapsedTimerInfo(startedAt: t0, pausedDuration: 0, pausedAt: t0.addingTimeInterval(30))
        #expect(info.interval.lowerBound == t0)
    }

    @Test func elapsedTimerMatchesSnapshotElapsed() {
        // The system timer shows pauseTime - lowerBound; that must equal the snapshot's elapsed time.
        let paused = t0.addingTimeInterval(600)
        let snapshot = SessionSnapshot(
            startedAt: t0, pausedDuration: 90, pausedAt: paused, exerciseCount: 1, entries: [])
        let info = ElapsedTimerInfo(
            startedAt: snapshot.startedAt, pausedDuration: snapshot.pausedDuration, pausedAt: snapshot.pausedAt)
        let shown = paused.timeIntervalSince(info.interval.lowerBound)
        #expect(shown == snapshot.elapsed(now: paused.addingTimeInterval(1_000)))
    }

    // MARK: Rest

    @Test func restIntervalCountsDownToTheEnd() {
        let end = t0.addingTimeInterval(90)
        let info = RestTimerInfo(endsAt: end, totalSeconds: 90, pausedAt: nil)
        #expect(info.interval.lowerBound == t0)
        #expect(info.interval.upperBound == end)
    }

    @Test func restIntervalIsValidForAZeroOrNegativeLength() {
        let end = t0.addingTimeInterval(5)
        #expect(RestTimerInfo(endsAt: end, totalSeconds: 0, pausedAt: nil).interval == end...end)
        #expect(RestTimerInfo(endsAt: end, totalSeconds: -3, pausedAt: nil).interval == end...end)
    }

    @Test func restIntervalFollowsARestShiftedByAResume() {
        // Resume moves restEndsAt later by the paused time; the interval moves with it.
        let end = t0.addingTimeInterval(90 + 40)
        let info = RestTimerInfo(endsAt: end, totalSeconds: 90, pausedAt: nil)
        #expect(info.interval.lowerBound == t0.addingTimeInterval(40))
    }

    @Test func progressRunsFromFullToEmpty() {
        let info = RestTimerInfo(endsAt: t0.addingTimeInterval(90), totalSeconds: 90, pausedAt: nil)
        #expect(info.progress(at: t0) == 1)
        #expect(info.progress(at: t0.addingTimeInterval(45)) == 0.5)
        #expect(info.progress(at: t0.addingTimeInterval(90)) == 0)
    }

    @Test func progressIsClampedOutsideTheRest() {
        let info = RestTimerInfo(endsAt: t0.addingTimeInterval(90), totalSeconds: 90, pausedAt: nil)
        #expect(info.progress(at: t0.addingTimeInterval(-10)) == 1)
        #expect(info.progress(at: t0.addingTimeInterval(200)) == 0)
    }

    @Test func progressIsFrozenWhilePaused() {
        let info = RestTimerInfo(
            endsAt: t0.addingTimeInterval(90), totalSeconds: 90, pausedAt: t0.addingTimeInterval(30))
        #expect(info.progress(at: t0.addingTimeInterval(80)) == 60.0 / 90.0)
        #expect(info.progress(at: t0.addingTimeInterval(5_000)) == 60.0 / 90.0)
    }

    @Test func progressIsZeroForARestWithNoLength() {
        let info = RestTimerInfo(endsAt: t0, totalSeconds: 0, pausedAt: nil)
        #expect(info.progress(at: t0) == 0)
    }

    // MARK: Frozen remaining

    @Test func frozenRemainingRoundsUp() {
        let info = RestTimerInfo(
            endsAt: t0.addingTimeInterval(90), totalSeconds: 90, pausedAt: t0.addingTimeInterval(0.8))
        #expect(info.frozenRemainingSeconds == 90)
        let exact = RestTimerInfo(
            endsAt: t0.addingTimeInterval(90), totalSeconds: 90, pausedAt: t0.addingTimeInterval(30))
        #expect(exact.frozenRemainingSeconds == 60)
    }

    @Test func frozenRemainingIsNeverNegative() {
        let info = RestTimerInfo(
            endsAt: t0.addingTimeInterval(90), totalSeconds: 90, pausedAt: t0.addingTimeInterval(200))
        #expect(info.frozenRemainingSeconds == 0)
    }

    @Test func frozenRemainingIsZeroWhenNotPaused() {
        #expect(RestTimerInfo(endsAt: t0.addingTimeInterval(90), totalSeconds: 90, pausedAt: nil).frozenRemainingSeconds == 0)
    }

    @Test func frozenRemainingMatchesSnapshotRestRemaining() {
        let paused = t0.addingTimeInterval(30.4)
        let snapshot = SessionSnapshot(
            startedAt: t0, pausedAt: paused, restEndsAt: t0.addingTimeInterval(90), exerciseCount: 1, entries: [])
        let info = RestTimerInfo(endsAt: t0.addingTimeInterval(90), totalSeconds: 90, pausedAt: paused)
        #expect(info.frozenRemainingSeconds == snapshot.restRemaining(now: paused.addingTimeInterval(500)))
    }
}
