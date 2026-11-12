import Foundation
import SwiftData
import Testing
@testable import WorkoutBuddy

/// Pause, resume, end early, back to workout, discard, save and End Workout for recovery of `SessionLibrary`.
@MainActor
struct SessionLibraryEndTests {
    private let t0 = SessionFixture.t0

    /// The shared store with a session already started.
    private struct Fixture {
        let base: SessionFixture
        let session: WorkoutSession
        let ids: [UUID]  // A, B, C
        var tc: TestContainer { base.tc }
        var lib: SessionLibrary { base.lib }
        var workout: Workout { base.workout }
        var context: ModelContext { base.context }
        var snapshot: SessionSnapshot { lib.snapshot(of: session) }
    }

    private func makeFixture() throws -> Fixture {
        let base = try SessionFixture.make()
        let (session, ids) = try base.start()
        return Fixture(base: base, session: session, ids: ids)
    }

    private func expectPersisted(_ f: Fixture, sourceLocation: SourceLocation = #_sourceLocation) throws {
        try f.base.expectPersisted(f.session, sourceLocation: sourceLocation)
    }

    /// Done A (t0+10), skip its rest, Done B (t0+20), Done C (t0+30): finished at t0+30.
    private func completeAll(_ f: Fixture) throws {
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)
        try f.lib.skipRest(in: f.session, now: t0 + 11)
        try f.lib.completeSet(in: f.session, setID: f.ids[1], reps: 8, kg: 62.5, now: t0 + 20)
        try f.lib.completeSet(in: f.session, setID: f.ids[2], reps: 5, kg: 100, now: t0 + 30)
    }

    private func skipAll(_ f: Fixture) throws {
        try f.lib.skipSet(in: f.session, setID: f.ids[0], now: t0 + 1)
        try f.lib.skipSet(in: f.session, setID: f.ids[1], now: t0 + 2)
        try f.lib.skipSet(in: f.session, setID: f.ids[2], now: t0 + 3)
    }

    private func modelSets(_ f: Fixture) -> [SessionSet] {
        f.session.orderedExercises.flatMap(\.orderedSets)
    }

    // MARK: Pause and resume

    @Test func pauseFreezesElapsedAndRestRemaining() throws {
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)  // rest to t0+100
        try f.lib.pause(in: f.session, now: t0 + 40)

        #expect(f.session.pausedAt == t0 + 40)
        #expect(f.snapshot.isPaused)
        #expect(f.snapshot.elapsed(now: t0 + 500) == 40)
        #expect(f.snapshot.restRemaining(now: t0 + 500) == 60)
        #expect(f.snapshot.screen(now: t0 + 500) == .rest(next: 1, remaining: 60))
        try expectPersisted(f)
    }

    @Test func pausingTwiceKeepsTheFirstPause() throws {
        let f = try makeFixture()
        try f.lib.pause(in: f.session, now: t0 + 10)
        try f.lib.pause(in: f.session, now: t0 + 20)
        #expect(f.session.pausedAt == t0 + 10)
    }

    @Test func resumeAddsToPausedDurationAndShiftsARunningRest() throws {
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)  // rest to t0+100
        try f.lib.pause(in: f.session, now: t0 + 40)
        try f.lib.resume(in: f.session, now: t0 + 100)

        #expect(f.session.pausedAt == nil)
        #expect(f.session.pausedDuration == 60)
        #expect(f.session.restEndsAt == t0 + 160)
        #expect(!f.snapshot.isPaused)
        #expect(f.snapshot.elapsed(now: t0 + 110) == 50)
        #expect(f.snapshot.restRemaining(now: t0 + 110) == 50)
        try expectPersisted(f)
    }

    @Test func resumeOnTheSetScreenOnlyAddsThePause() throws {
        let f = try makeFixture()
        try f.lib.pause(in: f.session, now: t0 + 10)
        try f.lib.resume(in: f.session, now: t0 + 25)
        #expect(f.session.pausedDuration == 15)
        #expect(f.session.restEndsAt == nil)
        #expect(f.snapshot.screen(now: t0 + 25) == .set(0))
    }

    @Test func pauseAfterTheRestExpiredAndLateResumeDoesNotBringTheRestBack() throws {
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)  // rest to t0+100
        try f.lib.pause(in: f.session, now: t0 + 150)
        #expect(f.session.restEndsAt == nil)  // The expired rest was cleared before pausing.
        try f.lib.resume(in: f.session, now: t0 + 200)
        #expect(f.session.restEndsAt == nil)
        #expect(f.session.pausedDuration == 50)
        #expect(f.snapshot.screen(now: t0 + 200) == .set(1))
    }

    @Test func resumeWhenNotPausedDoesNothing() throws {
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)
        let before = f.snapshot
        try f.lib.resume(in: f.session, now: t0 + 50)
        #expect(f.snapshot.ignoringLastAction() == before.ignoringLastAction())
    }

    @Test func pauseAndResumeOnAFinishedSessionDoNothing() throws {
        let f = try makeFixture()
        try completeAll(f)
        let before = f.snapshot
        try f.lib.pause(in: f.session, now: t0 + 100)
        try f.lib.resume(in: f.session, now: t0 + 200)
        #expect(f.snapshot == before)
    }

    // MARK: End early

    @Test func endEarlyKeepsPendingSetsPendingAndFinishes() throws {
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 12, kg: 65, now: t0 + 10)  // rest running
        try f.lib.endEarly(in: f.session, now: t0 + 20)

        let snapshot = f.snapshot
        #expect(snapshot.entries.map(\.status) == [.done, .pending, .pending])
        #expect(snapshot.entries[0].actualReps == 12)
        #expect(snapshot.entries[1].completedAt == nil)
        #expect(f.session.endedAt == t0 + 20)
        #expect(f.session.restEndsAt == nil)
        #expect(f.session.pausedAt == nil)
        #expect(f.session.status == .inProgress)  // Waiting for Save.
        #expect(snapshot.screen(now: t0 + 500) == .summary)
        #expect(SessionStats(snapshot, now: t0 + 500).duration == 20)
        // Pending sets count as not performed on the summary, before anything is final.
        #expect(SessionStats(snapshot, now: t0 + 500).notPerformedCount == 2)
        try expectPersisted(f)
    }

    @Test func endEarlyKeepsActualValuesLeftOnPendingSets() throws {
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)
        try f.lib.skipRest(in: f.session, now: t0 + 11)
        // Leftover values on a pending set, as an Undo leaves them.
        let c = try #require(modelSets(f).last)
        c.actualReps = 7
        c.actualKg = 90
        try f.context.save()
        try f.lib.endEarly(in: f.session, now: t0 + 30)

        let entries = f.snapshot.entries
        #expect(entries.map(\.status) == [.done, .pending, .pending])
        #expect(entries[2].actualReps == 7)
        #expect(entries[2].actualKg == 90)

        // Save is what marks them not performed and clears the values.
        try f.lib.save(f.session)
        let saved = f.snapshot.entries
        #expect(saved.map(\.status) == [.done, .notPerformed, .notPerformed])
        #expect(saved[2].actualReps == nil)
        #expect(saved[2].actualKg == nil)
        #expect(saved[2].completedAt == nil)
        #expect(f.session.status == .endedEarly)
        try expectPersisted(f)
    }

    @Test func endEarlyWhilePausedDoesNotSubtractThePauseTwice() throws {
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)
        try f.lib.pause(in: f.session, now: t0 + 20)
        try f.lib.endEarly(in: f.session, now: t0 + 80)

        let snapshot = f.snapshot
        #expect(f.session.pausedAt == nil)
        #expect(!snapshot.isPaused)
        #expect(f.session.pausedDuration == 60)
        #expect(f.session.endedAt == t0 + 80)
        #expect(f.session.restEndsAt == nil)
        #expect(snapshot.elapsed(now: t0 + 1000) == 20)
        #expect(SessionStats(snapshot, now: t0 + 1000).duration == 20)
        try expectPersisted(f)
    }

    @Test func endEarlyExcludesEarlierPausesFromTheDuration() throws {
        let f = try makeFixture()
        try f.lib.pause(in: f.session, now: t0 + 20)
        try f.lib.resume(in: f.session, now: t0 + 50)
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 60)
        try f.lib.endEarly(in: f.session, now: t0 + 100)
        #expect(SessionStats(f.snapshot, now: t0 + 100).duration == 70)
    }

    @Test func endEarlyWithNoDoneSetIsRefusedAlsoWhenSetsWereSkipped() throws {
        let f = try makeFixture()
        let untouched = f.snapshot
        try f.lib.endEarly(in: f.session, now: t0 + 5)
        #expect(f.snapshot.ignoringLastAction() == untouched.ignoringLastAction())

        try f.lib.skipSet(in: f.session, setID: f.ids[0], now: t0 + 10)
        let skipped = f.snapshot
        try f.lib.endEarly(in: f.session, now: t0 + 20)
        #expect(f.snapshot.ignoringLastAction() == skipped.ignoringLastAction())
        #expect(f.session.endedAt == nil)
    }

    @Test func endEarlyOnAFinishedSessionDoesNothing() throws {
        let f = try makeFixture()
        try completeAll(f)
        let before = f.snapshot
        try f.lib.endEarly(in: f.session, now: t0 + 100)
        #expect(f.snapshot == before)
    }

    // MARK: Discard

    @Test func discardRemovesTheSessionAndItsChildrenOnly() throws {
        let f = try makeFixture()
        try f.lib.skipSet(in: f.session, setID: f.ids[0], now: t0 + 1)
        try f.lib.discard(f.session)

        #expect(try f.context.fetchCount(FetchDescriptor<WorkoutSession>()) == 0)
        #expect(try f.context.fetchCount(FetchDescriptor<SessionExercise>()) == 0)
        #expect(try f.context.fetchCount(FetchDescriptor<SessionSet>()) == 0)
        #expect(try f.context.fetchCount(FetchDescriptor<Exercise>()) == 2)
        #expect(f.workout.sessions.isEmpty)
        #expect(try f.lib.activeSession() == nil)
        #expect(try f.lib.start(f.workout, now: t0 + 100).startedAt == t0 + 100)
        let fresh = ModelContext(f.tc.container)
        #expect(try fresh.fetchCount(FetchDescriptor<SessionSet>()) == 3)  // Only the new session's.
    }

    @Test func discardDoesNothingOnASavedSession() throws {
        let f = try makeFixture()
        try completeAll(f)
        try f.lib.save(f.session)
        try f.lib.discard(f.session)

        #expect(try f.context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1)
        #expect(try f.context.fetchCount(FetchDescriptor<SessionSet>()) == 3)
        #expect(f.session.status == .completed)
    }

    // MARK: Last action

    @Test func startAndEveryActionStampTheLastAction() throws {
        let f = try makeFixture()
        #expect(f.session.lastActionAt == t0)
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)
        #expect(f.session.lastActionAt == t0 + 10)
        try f.lib.pause(in: f.session, now: t0 + 20)
        #expect(f.session.lastActionAt == t0 + 20)
        try f.lib.resume(in: f.session, now: t0 + 30)
        #expect(f.session.lastActionAt == t0 + 30)
        try f.lib.undo(in: f.session, setID: f.ids[0], now: t0 + 40)
        #expect(f.session.lastActionAt == t0 + 40)
        try f.lib.skipSet(in: f.session, setID: f.ids[0], now: t0 + 50)
        #expect(f.session.lastActionAt == t0 + 50)
        try f.lib.finishRest(in: f.session, now: t0 + 55)
        #expect(f.session.lastActionAt == t0 + 55)
        try f.lib.completeSet(in: f.session, setID: f.ids[1], reps: 8, kg: 62.5, now: t0 + 60)
        try f.lib.completeSet(in: f.session, setID: f.ids[2], reps: 5, kg: 100, now: t0 + 70)  // Set C.
        #expect(f.session.lastActionAt == t0 + 70)
        try expectPersisted(f)
    }

    @Test func skipRestAndEndEarlyStampTheLastAction() throws {
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)
        try f.lib.skipRest(in: f.session, now: t0 + 15)
        #expect(f.session.lastActionAt == t0 + 15)
        try f.lib.endEarly(in: f.session, now: t0 + 25)
        #expect(f.session.lastActionAt == t0 + 25)
    }

    @Test func aFinishedSessionIsNotStampedAgain() throws {
        let f = try makeFixture()
        try completeAll(f)
        let stamped = f.session.lastActionAt
        try f.lib.pause(in: f.session, now: t0 + 500)
        #expect(f.session.lastActionAt == stamped)
    }

    // MARK: Save

    @Test func saveMarksACompleteWorkoutCompleted() throws {
        let f = try makeFixture()
        try completeAll(f)
        #expect(WorkoutLibrary(context: f.context).lastPerformed(f.workout) == nil)
        try f.lib.save(f.session)

        #expect(f.session.status == .completed)
        #expect(f.session.endedAt == t0 + 30)
        #expect(try f.lib.activeSession() == nil)
        #expect(WorkoutLibrary(context: f.context).lastPerformed(f.workout) == t0)
        try expectPersisted(f)
    }

    @Test func saveMarksAWorkoutWithSkippedSetsCompleted() throws {
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)
        try f.lib.skipRest(in: f.session, now: t0 + 11)
        try f.lib.skipSet(in: f.session, setID: f.ids[1], now: t0 + 20)
        try f.lib.skipSet(in: f.session, setID: f.ids[2], now: t0 + 30)
        try f.lib.save(f.session)
        #expect(f.session.status == .completed)
    }

    @Test func saveMarksAnEarlyEndedWorkoutEndedEarly() throws {
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)
        try f.lib.endEarly(in: f.session, now: t0 + 20)
        try f.lib.save(f.session)

        #expect(f.session.status == .endedEarly)
        #expect(f.snapshot.entries.map(\.status) == [.done, .notPerformed, .notPerformed])
        #expect(try f.lib.activeSession() == nil)
        #expect(WorkoutLibrary(context: f.context).lastPerformed(f.workout) == t0)
        try expectPersisted(f)
    }

    @Test func saveRefusesAFinishedSessionWhereEverySetWasSkipped() throws {
        let f = try makeFixture()
        try skipAll(f)
        #expect(f.session.endedAt != nil)
        try f.lib.save(f.session)

        #expect(f.session.status == .inProgress)
        #expect(try f.lib.activeSession()?.id == f.session.id)
        #expect(WorkoutLibrary(context: f.context).lastPerformed(f.workout) == nil)
        #expect(!f.context.hasChanges)
    }

    @Test func saveDoesNothingWhileTheWorkoutIsStillRunning() throws {
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)
        let before = f.snapshot
        try f.lib.save(f.session)
        #expect(f.snapshot == before)
        #expect(f.session.status == .inProgress)
    }

    @Test func savingTwiceChangesNothing() throws {
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)
        try f.lib.endEarly(in: f.session, now: t0 + 20)
        try f.lib.save(f.session)
        let saved = f.snapshot
        try f.lib.save(f.session)
        #expect(f.snapshot == saved)
        #expect(f.session.status == .endedEarly)
    }

    // MARK: Bad data: all sets resolved, no endedAt

    @Test func resolvedSetsWithoutEndedAtShowTheSummaryAndSaveEndsAtLastActivity() throws {
        let f = try makeFixture()
        try completeAll(f)
        // Bad data: the workout finished but `endedAt` was lost.
        f.session.endedAt = nil
        try f.context.save()
        #expect(f.snapshot.currentSetIndex == nil)
        #expect(LaunchRecovery.decide(f.snapshot) == .showSummary)

        try f.lib.save(f.session)
        #expect(f.session.endedAt == t0 + 30)
        #expect(f.session.status == .completed)
        #expect(f.session.pausedAt == nil)
        #expect(try f.lib.activeSession() == nil)
        try expectPersisted(f)
    }

    @Test func resolvedSetsWithoutEndedAtAndAPauseEndAtThePause() throws {
        let f = try makeFixture()
        try completeAll(f)
        f.session.endedAt = nil
        f.session.pausedAt = t0 + 45
        try f.context.save()
        try f.lib.save(f.session)

        #expect(f.session.endedAt == t0 + 45)
        #expect(f.session.pausedAt == nil)
        #expect(f.session.pausedDuration == 0)
        #expect(f.session.status == .completed)
    }

    // MARK: End Workout for recovery

    @Test func endForRecoveryEndsAtTheLatestDoneSetAndWaitsForSave() throws {
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)  // rest running
        try f.lib.endForRecovery(f.session)

        #expect(f.session.endedAt == t0 + 10)
        #expect(f.session.status == .inProgress)  // Waiting for Save on the summary.
        #expect(f.session.restEndsAt == nil)
        #expect(f.session.pausedAt == nil)
        #expect(f.snapshot.entries.map(\.status) == [.done, .pending, .pending])
        #expect(f.snapshot.screen(now: t0 + 9999) == .summary)
        #expect(try f.lib.activeSession()?.id == f.session.id)
        #expect(WorkoutLibrary(context: f.context).lastPerformed(f.workout) == nil)
        #expect(LaunchRecovery.decide(f.snapshot) == .showSummary)
        try expectPersisted(f)

        try f.lib.save(f.session)
        #expect(f.session.status == .endedEarly)
        #expect(f.snapshot.entries.map(\.status) == [.done, .notPerformed, .notPerformed])
        #expect(try f.lib.activeSession() == nil)
        #expect(WorkoutLibrary(context: f.context).lastPerformed(f.workout) == t0)
        try expectPersisted(f)
    }

    @Test func endForRecoveryEndsAtALaterSkippedSet() throws {
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)
        try f.lib.skipRest(in: f.session, now: t0 + 12)
        try f.lib.skipSet(in: f.session, setID: f.ids[1], now: t0 + 50)
        try f.lib.endForRecovery(f.session)

        #expect(f.session.endedAt == t0 + 50)
        #expect(f.snapshot.entries.map(\.status) == [.done, .skipped, .pending])
        try f.lib.save(f.session)
        #expect(f.session.status == .endedEarly)
        #expect(f.snapshot.entries.map(\.status) == [.done, .skipped, .notPerformed])
    }

    @Test func endForRecoveryEndsAtThePauseWhenPausedAndKeepsEarlierPauses() throws {
        let f = try makeFixture()
        try f.lib.pause(in: f.session, now: t0 + 20)
        try f.lib.resume(in: f.session, now: t0 + 50)
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 60)
        try f.lib.pause(in: f.session, now: t0 + 80)
        try f.lib.endForRecovery(f.session)

        #expect(f.session.endedAt == t0 + 80)
        #expect(f.session.pausedAt == nil)
        #expect(f.session.pausedDuration == 30)
        #expect(f.session.status == .inProgress)
        #expect(SessionStats(f.snapshot, now: t0 + 9999).duration == 50)
        try expectPersisted(f)
    }

    @Test func endForRecoveryCountsAPauseAndResumeAfterTheLastDoneSet() throws {
        // Started 9:50, Done A 10:00, paused 10:05, resumed 10:30, then the app was killed.
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 600)
        try f.lib.pause(in: f.session, now: t0 + 900)
        try f.lib.resume(in: f.session, now: t0 + 2400)
        try f.lib.endForRecovery(f.session)

        #expect(f.session.endedAt == t0 + 2400)
        #expect(f.session.pausedDuration == 1500)
        #expect(SessionStats(f.snapshot, now: t0 + 9999).duration == 15 * 60)
        try expectPersisted(f)
    }

    @Test func endForRecoveryWithNoDoneSetDoesNothing() throws {
        let f = try makeFixture()
        try f.lib.skipSet(in: f.session, setID: f.ids[0], now: t0 + 10)
        let before = f.snapshot
        try f.lib.endForRecovery(f.session)
        #expect(f.snapshot == before)
        #expect(f.session.endedAt == nil)
    }

    @Test func endForRecoveryOnAFinishedOrSavedSessionDoesNothing() throws {
        let f = try makeFixture()
        try completeAll(f)
        let finished = f.snapshot
        try f.lib.endForRecovery(f.session)
        #expect(f.snapshot == finished)
        try f.lib.save(f.session)
        let saved = f.snapshot
        try f.lib.endForRecovery(f.session)
        #expect(f.snapshot == saved)
        #expect(f.session.status == .completed)
    }

    // MARK: Back to Workout

    @Test func backToWorkoutAfterAnEarlyEndKeepsPendingSetsAndExcludesTheSummaryTime() throws {
        let f = try makeFixture()
        try f.lib.pause(in: f.session, now: t0 + 5)
        try f.lib.resume(in: f.session, now: t0 + 15)  // 10 s paused
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 20)  // rest to t0+110
        try f.lib.endEarly(in: f.session, now: t0 + 30)
        try f.lib.backToWorkout(in: f.session, now: t0 + 130)  // 100 s on the summary

        #expect(f.session.endedAt == nil)
        #expect(f.session.pausedAt == nil)
        #expect(f.session.restEndsAt == nil)  // The rest isn't restored.
        #expect(f.session.status == .inProgress)
        #expect(f.session.pausedDuration == 110)
        #expect(f.session.lastActionAt == t0 + 130)
        #expect(f.snapshot.entries.map(\.status) == [.done, .pending, .pending])
        #expect(f.snapshot.screen(now: t0 + 130) == .set(1))
        // Elapsed: 130 s since the start, minus 10 s paused and 100 s on the summary.
        #expect(f.snapshot.elapsed(now: t0 + 130) == 20)
        #expect(f.snapshot.elapsed(now: t0 + 150) == 40)
        try expectPersisted(f)

        // The workout carries on, and can be ended and saved again.
        try f.lib.completeSet(in: f.session, setID: f.ids[1], reps: 8, kg: 62.5, now: t0 + 140)
        try f.lib.completeSet(in: f.session, setID: f.ids[2], reps: 5, kg: 100, now: t0 + 150)
        try f.lib.save(f.session)
        #expect(f.session.status == .completed)
        #expect(SessionStats(f.snapshot, now: t0 + 9999).duration == 40)
    }

    @Test func backToWorkoutAfterDoneOnTheLastSetPutsThatSetBackWithItsValues() throws {
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)
        try f.lib.skipRest(in: f.session, now: t0 + 11)
        try f.lib.completeSet(in: f.session, setID: f.ids[1], reps: 8, kg: 62.5, now: t0 + 20)
        try f.lib.completeSet(in: f.session, setID: f.ids[2], reps: 6, kg: 105, now: t0 + 30)  // Accidental.
        #expect(f.session.endedAt == t0 + 30)
        try f.lib.backToWorkout(in: f.session, now: t0 + 50)

        let snapshot = f.snapshot
        #expect(snapshot.entries.map(\.status) == [.done, .done, .pending])
        #expect(snapshot.entries[2].actualReps == 6)
        #expect(snapshot.entries[2].actualKg == 105)
        #expect(snapshot.entries[2].completedAt == nil)
        #expect(snapshot.prefill(forSetAt: 2) == (6, 105))
        #expect(snapshot.screen(now: t0 + 50) == .set(2))
        #expect(f.session.endedAt == nil)
        #expect(f.session.pausedDuration == 20)
        #expect(f.session.restEndsAt == nil)
        try expectPersisted(f)
    }

    @Test func backToWorkoutAfterSkipOnTheLastSetPutsThatSetBack() throws {
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)
        try f.lib.skipRest(in: f.session, now: t0 + 11)
        try f.lib.completeSet(in: f.session, setID: f.ids[1], reps: 8, kg: 62.5, now: t0 + 20)
        try f.lib.skipSet(in: f.session, setID: f.ids[2], now: t0 + 30)
        try f.lib.backToWorkout(in: f.session, now: t0 + 40)

        #expect(f.snapshot.entries.map(\.status) == [.done, .done, .pending])
        #expect(f.snapshot.entries[2].completedAt == nil)
        #expect(f.snapshot.screen(now: t0 + 40) == .set(2))
        #expect(f.session.pausedDuration == 10)
    }

    @Test func backToWorkoutAfterEverySetWasSkippedWorksToo() throws {
        let f = try makeFixture()
        try skipAll(f)
        try f.lib.backToWorkout(in: f.session, now: t0 + 10)
        #expect(f.snapshot.entries.map(\.status) == [.skipped, .skipped, .pending])
        #expect(f.snapshot.screen(now: t0 + 10) == .set(2))
    }

    @Test func backToWorkoutIsRefusedOnARunningOrSavedSession() throws {
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)
        let running = f.snapshot
        try f.lib.backToWorkout(in: f.session, now: t0 + 50)
        #expect(f.snapshot == running)

        try f.lib.endEarly(in: f.session, now: t0 + 60)
        try f.lib.save(f.session)
        let saved = f.snapshot
        try f.lib.backToWorkout(in: f.session, now: t0 + 70)
        #expect(f.snapshot == saved)
        #expect(f.session.status == .endedEarly)
        #expect(f.session.endedAt == t0 + 60)
    }

    @Test func backToWorkoutOnTheBadDataSummaryTreatsLastActivityAsTheEnd() throws {
        let f = try makeFixture()
        try completeAll(f)
        f.session.endedAt = nil  // Bad data: all sets resolved, `endedAt` lost.
        try f.context.save()
        #expect(LaunchRecovery.decide(f.snapshot) == .showSummary)
        try f.lib.backToWorkout(in: f.session, now: t0 + 100)

        #expect(f.session.endedAt == nil)
        #expect(f.session.pausedAt == nil)
        #expect(f.session.pausedDuration == 70)  // From the last activity (t0+30) to now.
        #expect(f.snapshot.entries.map(\.status) == [.done, .done, .pending])
        #expect(f.snapshot.screen(now: t0 + 100) == .set(2))
        #expect(f.snapshot.elapsed(now: t0 + 100) == 30)
        try expectPersisted(f)
    }

    @Test func backToWorkoutAfterARecoveryEndExcludesTheTimeSinceTheLastActivity() throws {
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)
        try f.lib.skipRest(in: f.session, now: t0 + 12)
        try f.lib.endForRecovery(f.session)  // Ends at t0+12.
        try f.lib.backToWorkout(in: f.session, now: t0 + 40_000)  // Resumed much later.

        #expect(f.session.pausedDuration == 39_988)
        #expect(f.snapshot.elapsed(now: t0 + 40_000) == 12)
    }

    // MARK: Persistence

    @Test func everyActionIsSavedAndReadsBackFromAFreshContext() throws {
        let f = try makeFixture()
        try f.lib.completeSet(in: f.session, setID: f.ids[0], reps: 10, kg: 60, now: t0 + 10)
        try f.lib.pause(in: f.session, now: t0 + 20)
        try expectPersisted(f)
        try f.lib.resume(in: f.session, now: t0 + 30)
        try expectPersisted(f)
        try f.lib.endEarly(in: f.session, now: t0 + 40)
        try expectPersisted(f)
        try f.lib.save(f.session)
        try expectPersisted(f)
        #expect(!f.context.hasChanges)
    }
}
