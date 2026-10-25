import Foundation
import SwiftData
import Testing
@testable import WorkoutBuddy

/// Looking back at earlier sets: `editDoneSet`, `markSkippedAsDone` and `markDoneAsSkipped` of `SessionLibrary`.
@MainActor
struct SessionLibraryReviewTests {
    private let t0 = SessionFixture.t0

    private struct Fixture {
        let base: SessionFixture
        let session: WorkoutSession
        let ids: [UUID]  // A, B, C
        var lib: SessionLibrary { base.lib }
        var snapshot: SessionSnapshot { lib.snapshot(of: session) }
    }

    private func makeFixture() throws -> Fixture {
        let base = try SessionFixture.make()
        let (session, ids) = try base.start()
        return Fixture(base: base, session: session, ids: ids)
    }

    /// A done (10 x 60 at t0+10), B skipped (t0+20): running, on C.
    private func runningOnC(_ f: Fixture) throws {
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)
        try f.lib.skipRest(in: f.session, now: t0 + 11)
        try f.lib.skipSet(in: f.session, setID: f.ids[1], now: t0 + 20)
    }

    /// A done (10 x 60), B done (8 x 62.5), C done (5 x 100): finished at t0+30, waiting for Save.
    private func finishedAllDone(_ f: Fixture) throws {
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)
        try f.lib.skipRest(in: f.session, now: t0 + 11)
        try f.lib.completeSet(in: f.session, setID: f.ids[1], reps: 8, kg: 62.5, now: t0 + 20)
        try f.lib.completeSet(in: f.session, setID: f.ids[2], reps: 5, kg: 100, now: t0 + 30)
    }

    private func finishedAllSkipped(_ f: Fixture) throws {
        try f.lib.skipSet(in: f.session, setID: f.ids[0], now: t0 + 1)
        try f.lib.skipSet(in: f.session, setID: f.ids[1], now: t0 + 2)
        try f.lib.skipSet(in: f.session, setID: f.ids[2], now: t0 + 3)
    }

    // MARK: editDoneSet

    @Test func editDoneSetStoresClampedAndSnappedValuesAndKeepsCompletedAt() throws {
        let f = try makeFixture()
        try runningOnC(f)
        try f.lib.editDoneSet(in: f.session, setID: f.ids[0], reps: 12, kg: 62.3, now: t0 + 40)

        let entry = f.snapshot.entries[0]
        #expect(entry.status == .done)
        #expect(entry.actualReps == 12)
        #expect(entry.actualKg == 62.5)
        #expect(entry.completedAt == t0 + 10)
        try f.base.expectPersisted(f.session)

        try f.lib.editDoneSet(in: f.session, setID: f.ids[0], reps: 0, kg: -5, now: t0 + 41)
        #expect(f.snapshot.entries[0].actualReps == 1)
        #expect(f.snapshot.entries[0].actualKg == 0)
        try f.lib.editDoneSet(in: f.session, setID: f.ids[0], reps: 999, kg: 9_999, now: t0 + 42)
        #expect(f.snapshot.entries[0].actualReps == 100)
        #expect(f.snapshot.entries[0].actualKg == 500)
    }

    @Test func editDoneSetDoesNotMoveThePositionOrTheTimers() throws {
        let f = try makeFixture()
        try runningOnC(f)
        let before = f.snapshot
        try f.lib.editDoneSet(in: f.session, setID: f.ids[0], reps: 11, kg: 65, now: t0 + 40)

        let after = f.snapshot
        #expect(after.screen(now: t0 + 40) == before.screen(now: t0 + 40))
        #expect(after.currentSetIndex == before.currentSetIndex)
        #expect(after.pausedDuration == before.pausedDuration)
        #expect(after.pausedAt == before.pausedAt)
        #expect(after.restEndsAt == before.restEndsAt)
        #expect(after.elapsed(now: t0 + 50) == before.elapsed(now: t0 + 50))
    }

    @Test func aNoOpEditChangesNothingAndDoesNotStamp() throws {
        let f = try makeFixture()
        try runningOnC(f)
        let before = f.snapshot
        // The same values, and values that clamp or snap to the stored ones.
        try f.lib.editDoneSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 40)
        try f.lib.editDoneSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60.2, now: t0 + 41)
        #expect(f.snapshot == before)
        #expect(f.session.lastActionAt == before.lastActionAt)
    }

    @Test func editDoneSetStampsTheLastActionWhileRunning() throws {
        let f = try makeFixture()
        try runningOnC(f)
        try f.lib.editDoneSet(in: f.session, setID: f.ids[0], reps: 11, kg: 60, now: t0 + 40)
        #expect(f.session.lastActionAt == t0 + 40)
    }

    @Test func editDoneSetOnAFinishedSessionKeepsEndedAtAndDuration() throws {
        let f = try makeFixture()
        try finishedAllDone(f)
        let before = f.snapshot
        try f.lib.editDoneSet(in: f.session, setID: f.ids[1], reps: 9, kg: 65, now: t0 + 500)

        let after = f.snapshot
        #expect(after.entries[1].actualReps == 9)
        #expect(after.entries[1].actualKg == 65)
        #expect(f.session.endedAt == t0 + 30)
        #expect(f.session.lastActionAt == before.lastActionAt)
        #expect(f.session.status == .inProgress)
        #expect(SessionStats(after, now: t0 + 9_999).duration == SessionStats(before, now: t0 + 9_999).duration)
        #expect(SessionStats(after, now: t0 + 9_999).duration == 30)
        try f.base.expectPersisted(f.session)
    }

    @Test func editDoneSetIsRefusedOnPendingSkippedAndNotPerformedSets() throws {
        let f = try makeFixture()
        try runningOnC(f)
        let before = f.snapshot
        try f.lib.editDoneSet(in: f.session, setID: f.ids[2], reps: 9, kg: 9, now: t0 + 40)  // Pending (current).
        try f.lib.editDoneSet(in: f.session, setID: f.ids[1], reps: 9, kg: 9, now: t0 + 41)  // Skipped.
        #expect(f.snapshot == before)

        // Not performed: end early, then save.
        try f.lib.endEarly(in: f.session, now: t0 + 50)
        try f.lib.save(f.session)
        let saved = f.snapshot
        try f.lib.editDoneSet(in: f.session, setID: f.ids[2], reps: 9, kg: 9, now: t0 + 60)
        #expect(f.snapshot == saved)
        #expect(saved.entries[2].status == .notPerformed)
    }

    @Test func editDoneSetIsRefusedOnASavedSessionAndForAnUnknownID() throws {
        let f = try makeFixture()
        try finishedAllDone(f)
        try f.lib.editDoneSet(in: f.session, setID: UUID(), reps: 9, kg: 9, now: t0 + 40)
        try f.lib.save(f.session)
        let saved = f.snapshot
        try f.lib.editDoneSet(in: f.session, setID: f.ids[0], reps: 9, kg: 9, now: t0 + 60)
        #expect(f.snapshot == saved)
        #expect(f.session.status == .completed)
    }

    @Test func editedValuesCountInTheVolume() throws {
        let f = try makeFixture()
        try finishedAllDone(f)
        // 10 x 60 + 8 x 62.5 + 5 x 100 = 600 + 500 + 500
        #expect(SessionStats(f.snapshot, now: t0).volume == 1_600)
        try f.lib.editDoneSet(in: f.session, setID: f.ids[0], reps: 10, kg: 70, now: t0 + 40)
        #expect(SessionStats(f.snapshot, now: t0).volume == 1_700)
    }

    // MARK: markSkippedAsDone

    @Test func markSkippedAsDoneSetsStatusAndValuesAndKeepsTheSkipTime() throws {
        let f = try makeFixture()
        try runningOnC(f)
        try f.lib.markSkippedAsDone(in: f.session, setID: f.ids[1], reps: 7, kg: 61.1, now: t0 + 40)

        let entry = f.snapshot.entries[1]
        #expect(entry.status == .done)
        #expect(entry.actualReps == 7)
        #expect(entry.actualKg == 61)
        #expect(entry.completedAt == t0 + 20)
        #expect(f.snapshot.currentSetIndex == 2)
        #expect(f.session.lastActionAt == t0 + 40)
        try f.base.expectPersisted(f.session)
    }

    @Test func anAllSkippedWorkoutBecomesSaveableWhenASetIsMarkedDone() throws {
        let f = try makeFixture()
        try finishedAllSkipped(f)
        #expect(!SessionStats(f.snapshot, now: t0).canSave)
        try f.lib.save(f.session)
        #expect(f.session.status == .inProgress)  // Refused.

        try f.lib.markSkippedAsDone(in: f.session, setID: f.ids[1], reps: 8, kg: 60, now: t0 + 100)
        let snapshot = f.snapshot
        #expect(SessionStats(snapshot, now: t0).canSave)
        #expect(SessionStats(snapshot, now: t0).doneCount == 1)
        #expect(SessionStats(snapshot, now: t0).skippedCount == 2)
        // A finished session keeps its end and last action.
        #expect(f.session.endedAt == t0 + 3)
        #expect(f.session.lastActionAt == t0 + 3)

        try f.lib.save(f.session)
        #expect(f.session.status == .completed)
    }

    @Test func markSkippedAsDoneIsRefusedOnDonePendingAndNotPerformedSets() throws {
        let f = try makeFixture()
        try runningOnC(f)
        let before = f.snapshot
        try f.lib.markSkippedAsDone(in: f.session, setID: f.ids[0], reps: 1, kg: 1, now: t0 + 40)  // Done.
        try f.lib.markSkippedAsDone(in: f.session, setID: f.ids[2], reps: 1, kg: 1, now: t0 + 41)  // Pending.
        try f.lib.markSkippedAsDone(in: f.session, setID: UUID(), reps: 1, kg: 1, now: t0 + 42)
        #expect(f.snapshot == before)

        try f.lib.endEarly(in: f.session, now: t0 + 50)
        try f.lib.save(f.session)
        let saved = f.snapshot
        try f.lib.markSkippedAsDone(in: f.session, setID: f.ids[2], reps: 1, kg: 1, now: t0 + 60)  // Not performed.
        try f.lib.markSkippedAsDone(in: f.session, setID: f.ids[1], reps: 1, kg: 1, now: t0 + 61)  // Skipped, but saved.
        #expect(f.snapshot == saved)
    }

    // MARK: markDoneAsSkipped

    @Test func markDoneAsSkippedClearsTheValuesAndKeepsCompletedAt() throws {
        let f = try makeFixture()
        try runningOnC(f)
        try f.lib.markDoneAsSkipped(in: f.session, setID: f.ids[0], now: t0 + 40)

        let entry = f.snapshot.entries[0]
        #expect(entry.status == .skipped)
        #expect(entry.actualReps == nil)
        #expect(entry.actualKg == nil)
        #expect(entry.completedAt == t0 + 10)
        #expect(f.snapshot.currentSetIndex == 2)
        #expect(f.session.lastActionAt == t0 + 40)
        try f.base.expectPersisted(f.session)
    }

    @Test func markingTheOnlyDoneSetAsSkippedMakesTheWorkoutUnsaveable() throws {
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)
        try f.lib.skipRest(in: f.session, now: t0 + 11)
        try f.lib.skipSet(in: f.session, setID: f.ids[1], now: t0 + 20)
        try f.lib.skipSet(in: f.session, setID: f.ids[2], now: t0 + 30)
        #expect(SessionStats(f.snapshot, now: t0).canSave)

        try f.lib.markDoneAsSkipped(in: f.session, setID: f.ids[0], now: t0 + 100)
        let snapshot = f.snapshot
        #expect(!SessionStats(snapshot, now: t0).canSave)
        #expect(SessionStats(snapshot, now: t0).volume == 0)
        #expect(snapshot.screen(now: t0 + 100) == .summary)
        #expect(f.session.endedAt == t0 + 30)
        try f.lib.save(f.session)
        #expect(f.session.status == .inProgress)  // Refused: nothing was done.
    }

    @Test func markDoneAsSkippedIsRefusedOnSkippedPendingAndSavedSets() throws {
        let f = try makeFixture()
        try runningOnC(f)
        let before = f.snapshot
        try f.lib.markDoneAsSkipped(in: f.session, setID: f.ids[1], now: t0 + 40)  // Skipped.
        try f.lib.markDoneAsSkipped(in: f.session, setID: f.ids[2], now: t0 + 41)  // Pending.
        try f.lib.markDoneAsSkipped(in: f.session, setID: UUID(), now: t0 + 42)
        #expect(f.snapshot == before)

        try f.lib.endEarly(in: f.session, now: t0 + 50)
        try f.lib.save(f.session)
        let saved = f.snapshot
        try f.lib.markDoneAsSkipped(in: f.session, setID: f.ids[0], now: t0 + 60)
        #expect(f.snapshot == saved)
        #expect(f.session.status == .endedEarly)
    }

    @Test func aDoneSetMarkedAsSkippedCanBeMarkedDoneAgain() throws {
        let f = try makeFixture()
        try runningOnC(f)
        try f.lib.markDoneAsSkipped(in: f.session, setID: f.ids[0], now: t0 + 40)
        try f.lib.markSkippedAsDone(in: f.session, setID: f.ids[0], reps: 9, kg: 55, now: t0 + 41)
        let entry = f.snapshot.entries[0]
        #expect(entry.status == .done)
        #expect(entry.actualReps == 9)
        #expect(entry.actualKg == 55)
    }

    // MARK: Rests and pauses

    @Test func reviewEditsDontTouchARunningRestOrAPause() throws {
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)  // Rest to t0+100.
        try f.lib.skipRest(in: f.session, now: t0 + 11)
        try f.lib.completeSet(in: f.session, setID: f.ids[1], reps: 8, kg: 62.5, now: t0 + 20)  // Rest 0: on C.
        try f.lib.pause(in: f.session, now: t0 + 25)
        let before = f.snapshot
        try f.lib.editDoneSet(in: f.session, setID: f.ids[0], reps: 12, kg: 60, now: t0 + 30)
        try f.lib.markDoneAsSkipped(in: f.session, setID: f.ids[1], now: t0 + 31)

        let after = f.snapshot
        #expect(after.pausedAt == before.pausedAt)
        #expect(after.pausedDuration == before.pausedDuration)
        #expect(after.restEndsAt == before.restEndsAt)
        #expect(after.isPaused)
        #expect(after.elapsed(now: t0 + 500) == 25)
    }

    // MARK: Further edge cases

    @Test func editDoneSetWithAnUnknownIDChangesNothingAndDoesNotStamp() throws {
        let f = try makeFixture()
        try runningOnC(f)
        let before = f.snapshot
        try f.lib.editDoneSet(in: f.session, setID: UUID(), reps: 9, kg: 9, now: t0 + 40)
        #expect(f.snapshot == before)
        #expect(f.session.lastActionAt == before.lastActionAt)
        #expect(!f.base.context.hasChanges)
    }

    @Test func markSkippedAsDoneClampsTheReps() throws {
        let f = try makeFixture()
        try runningOnC(f)
        try f.lib.markSkippedAsDone(in: f.session, setID: f.ids[1], reps: 0, kg: 60, now: t0 + 40)
        #expect(f.snapshot.entries[1].actualReps == 1)
        try f.lib.markDoneAsSkipped(in: f.session, setID: f.ids[1], now: t0 + 41)
        try f.lib.markSkippedAsDone(in: f.session, setID: f.ids[1], reps: 999, kg: 600, now: t0 + 42)
        #expect(f.snapshot.entries[1].actualReps == 100)
        #expect(f.snapshot.entries[1].actualKg == 500)
    }

    @Test func markingSetsOnAFinishedSessionLeavesLastActionAtAndEndedAtAlone() throws {
        let f = try makeFixture()
        try finishedAllDone(f)  // Finished at t0+30; the last action was then too.
        let lastAction = f.session.lastActionAt
        #expect(lastAction == t0 + 30)

        try f.lib.markDoneAsSkipped(in: f.session, setID: f.ids[1], now: t0 + 500)
        #expect(f.snapshot.entries[1].status == .skipped)
        #expect(f.session.lastActionAt == lastAction)
        #expect(f.session.endedAt == t0 + 30)

        try f.lib.markSkippedAsDone(in: f.session, setID: f.ids[1], reps: 8, kg: 62.5, now: t0 + 600)
        #expect(f.snapshot.entries[1].status == .done)
        #expect(f.session.lastActionAt == lastAction)
        #expect(f.session.endedAt == t0 + 30)
        #expect(SessionStats(f.snapshot, now: t0 + 9_999).duration == 30)
    }
}
