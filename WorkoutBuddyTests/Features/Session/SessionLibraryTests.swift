import Foundation
import SwiftData
import Testing
@testable import WorkoutBuddy

@MainActor
struct SessionLibraryTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    /// Bench: A (10 x 60, rest 90), B (8 x 62.5, rest 0). Squat: C (5 x 100, rest 120).
    private let setA = SetValues(reps: 10, kg: 60, restSeconds: 90)
    private let setB = SetValues(reps: 8, kg: 62.5, restSeconds: 0)
    private let setC = SetValues(reps: 5, kg: 100, restSeconds: 120)

    private struct Fixture {
        let tc: TestContainer
        let lib: SessionLibrary
        let bench: Exercise
        let squat: Exercise
        let workout: Workout
        var context: ModelContext { tc.context }
    }

    private func makeFixture() throws -> Fixture {
        let tc = try TestContainer()
        let bench = Exercise(name: "Bench Press", muscleGroup: .chest)
        let squat = Exercise(name: "Back Squat", muscleGroup: .legs)
        tc.context.insert(bench)
        tc.context.insert(squat)
        try tc.context.save()
        let draft = WorkoutDraft(
            name: "Push Day",
            exercises: [
                DraftExercise(exerciseID: bench.id, sets: [DraftSet(values: setA), DraftSet(values: setB)]),
                DraftExercise(exerciseID: squat.id, sets: [DraftSet(values: setC)]),
            ])
        let workout = try WorkoutLibrary(context: tc.context).save(draft, to: nil, now: t0)
        return Fixture(tc: tc, lib: SessionLibrary(context: tc.context), bench: bench, squat: squat, workout: workout)
    }

    /// A started session plus its set IDs in order (A, B, C).
    private func started(_ f: Fixture, at now: Date? = nil) throws -> (WorkoutSession, [UUID]) {
        let session = try f.lib.start(f.workout, now: now ?? t0)
        return (session, f.lib.snapshot(of: session).entries.map(\.id))
    }

    private func modelSets(_ session: WorkoutSession) -> [SessionSet] {
        session.orderedExercises.flatMap(\.orderedSets)
    }

    /// Whether what's in the store (read through a fresh context) equals the session's snapshot.
    private func expectPersisted(_ f: Fixture, _ session: WorkoutSession, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let fresh = ModelContext(f.tc.container)
        let sessionID = session.id
        let fetched = try fresh.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID }))
        let reloaded = try #require(fetched.first, sourceLocation: sourceLocation)
        #expect(
            SessionLibrary(context: fresh).snapshot(of: reloaded) == f.lib.snapshot(of: session),
            sourceLocation: sourceLocation)
    }

    // MARK: Start

    @Test func startCopiesRowsInOrderWithPlannedNumbersAndExerciseRefs() throws {
        let f = try makeFixture()
        let session = try f.lib.start(f.workout, now: t0)
        let snapshot = f.lib.snapshot(of: session)

        #expect(snapshot.startedAt == t0)
        #expect(snapshot.endedAt == nil)
        #expect(snapshot.status == .inProgress)
        #expect(snapshot.exerciseCount == 2)
        #expect(snapshot.entries.map(\.planned) == [setA, setB, setC])
        #expect(snapshot.entries.map(\.exerciseIndex) == [0, 0, 1])
        #expect(snapshot.entries.map(\.setIndex) == [0, 1, 0])
        #expect(snapshot.entries.map(\.exerciseID) == [f.bench.id, f.bench.id, f.squat.id])
        #expect(snapshot.entries.allSatisfy { $0.status == .pending && $0.actualReps == nil && $0.actualKg == nil })
        #expect(session.workout?.id == f.workout.id)
        #expect(session.orderedExercises.map(\.order) == [0, 1])
        #expect(try f.lib.activeSession()?.id == session.id)
        try expectPersisted(f, session)
    }

    @Test func startSkipsRowsWithoutAnExerciseAndRenumbers() throws {
        let tc = try TestContainer()
        let bench = Exercise(name: "Bench Press", muscleGroup: .chest)
        tc.context.insert(bench)
        let workout = Workout(name: "Odd")
        tc.context.insert(workout)
        let orphan = WorkoutExercise(order: 0, exercise: nil)
        tc.context.insert(orphan)
        orphan.workout = workout
        let real = WorkoutExercise(order: 1, exercise: nil)
        tc.context.insert(real)
        real.workout = workout
        real.exercise = bench
        let planned = PlannedSet(order: 0, reps: 6, kg: 50, restSeconds: 60)
        tc.context.insert(planned)
        planned.workoutExercise = real
        try tc.context.save()

        let lib = SessionLibrary(context: tc.context)
        let session = try lib.start(workout, now: t0)
        #expect(session.orderedExercises.map(\.order) == [0])
        #expect(session.orderedExercises.first?.exercise?.id == bench.id)
        #expect(lib.snapshot(of: session).entries.map(\.planned) == [SetValues(reps: 6, kg: 50, restSeconds: 60)])
    }

    @Test func sessionShowsRenamedExerciseNames() throws {
        let f = try makeFixture()
        let session = try f.lib.start(f.workout, now: t0)
        f.bench.name = "Flat Bench"
        try f.context.save()
        #expect(session.orderedExercises.first?.exercise?.name == "Flat Bench")
    }

    @Test func startRefusesSecondSessionWithoutChangingTheStore() throws {
        let f = try makeFixture()
        _ = try f.lib.start(f.workout, now: t0)
        #expect(throws: SessionError.alreadyActive) { try f.lib.start(f.workout, now: t0 + 10) }
        #expect(!f.context.hasChanges)
        #expect(try f.context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1)
        #expect(try f.context.fetchCount(FetchDescriptor<SessionSet>()) == 3)
    }

    @Test func startRefusesSoftDeletedTemplate() throws {
        let f = try makeFixture()
        try WorkoutLibrary(context: f.context).softDelete(f.workout)
        #expect(throws: SessionError.cannotStart) { try f.lib.start(f.workout, now: t0) }
        #expect(!f.context.hasChanges)
        #expect(try f.context.fetchCount(FetchDescriptor<WorkoutSession>()) == 0)
    }

    @Test func startRefusesEmptyTemplate() throws {
        let f = try makeFixture()
        let empty = Workout(name: "Empty")
        f.context.insert(empty)
        try f.context.save()
        #expect(throws: SessionError.cannotStart) { try f.lib.start(empty, now: t0) }
        #expect(!f.context.hasChanges)
        #expect(try f.context.fetchCount(FetchDescriptor<WorkoutSession>()) == 0)
        #expect(try f.context.fetchCount(FetchDescriptor<SessionExercise>()) == 0)
    }

    @Test func startRefusesWhileASessionWaitsForSave() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        try completeAll(f, session, ids, start: t0)
        #expect(session.endedAt != nil)
        #expect(session.status == .inProgress)
        #expect(throws: SessionError.alreadyActive) { try f.lib.start(f.workout, now: t0 + 100) }
        #expect(!f.context.hasChanges)
        #expect(try f.context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1)
    }

    @Test func startAllowedAfterPreviousSessionIsFinishedAndSaved() throws {
        let f = try makeFixture()
        let (session, _) = try started(f)
        session.status = .completed
        try f.context.save()
        #expect(try f.lib.activeSession() == nil)
        _ = try f.lib.start(f.workout, now: t0 + 100)
        #expect(try f.lib.activeSession() != nil)
    }

    @Test func activeSessionPicksNewestStart() throws {
        let f = try makeFixture()
        let older = WorkoutSession(workout: nil, startedAt: t0)
        let newer = WorkoutSession(workout: nil, startedAt: t0 + 500)
        f.context.insert(older)
        f.context.insert(newer)
        try f.context.save()
        #expect(try f.lib.activeSession()?.id == newer.id)
    }

    @Test func editingTheTemplateAfterStartLeavesPlannedNumbersAlone() throws {
        let f = try makeFixture()
        let (session, _) = try started(f)
        var draft = WorkoutLibrary(context: f.context).draft(for: f.workout)
        draft.exercises[0].sets[0].values = SetValues(reps: 3, kg: 200, restSeconds: 15)
        draft.exercises.removeLast()
        try WorkoutLibrary(context: f.context).save(draft, to: f.workout, now: t0 + 50)

        let snapshot = f.lib.snapshot(of: session)
        #expect(snapshot.entries.map(\.planned) == [setA, setB, setC])
        #expect(snapshot.exerciseCount == 2)
    }

    // MARK: Done

    @Test func doneWithRestStartsTheRest() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        try f.lib.completeSet(in: session, setID: ids[0], reps: 12, kg: 65, now: t0 + 30)

        let snapshot = f.lib.snapshot(of: session)
        let a = snapshot.entries[0]
        #expect(a.status == .done)
        #expect(a.actualReps == 12)
        #expect(a.actualKg == 65)
        #expect(a.completedAt == t0 + 30)
        #expect(session.restEndsAt == t0 + 120)
        #expect(snapshot.screen(now: t0 + 31) == .rest(next: 1, remaining: 89))
        try expectPersisted(f, session)
    }

    @Test func doneWithoutRestOpensTheNextSet() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        try f.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0)
        try f.lib.skipRest(in: session, now: t0 + 1)
        try f.lib.completeSet(in: session, setID: ids[1], reps: 8, kg: 62.5, now: t0 + 60)

        let snapshot = f.lib.snapshot(of: session)
        #expect(session.restEndsAt == nil)
        #expect(snapshot.screen(now: t0 + 60) == .set(2))
        #expect(session.endedAt == nil)
        try expectPersisted(f, session)
    }

    @Test func doneOnTheLastSetFinishesTheWorkout() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        try completeAll(f, session, ids, start: t0)

        let snapshot = f.lib.snapshot(of: session)
        #expect(session.endedAt == t0 + 30)
        #expect(session.restEndsAt == nil)
        #expect(session.pausedAt == nil)
        #expect(session.status == .inProgress)
        #expect(snapshot.isFinished)
        #expect(snapshot.screen(now: t0 + 1000) == .summary)
        try expectPersisted(f, session)
    }

    /// Completes A, skips its rest, completes B and C, each 10 s after the previous.
    private func completeAll(_ f: Fixture, _ session: WorkoutSession, _ ids: [UUID], start: Date) throws {
        try f.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: start + 10)
        try f.lib.skipRest(in: session, now: start + 11)
        try f.lib.completeSet(in: session, setID: ids[1], reps: 8, kg: 62.5, now: start + 20)
        try f.lib.completeSet(in: session, setID: ids[2], reps: 5, kg: 100, now: start + 30)
    }

    @Test func actualValuesAreClampedAndSnapped() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        try f.lib.completeSet(in: session, setID: ids[0], reps: 500, kg: 62.3, now: t0)
        try f.lib.skipRest(in: session, now: t0)
        try f.lib.completeSet(in: session, setID: ids[1], reps: 0, kg: -5, now: t0)
        try f.lib.completeSet(in: session, setID: ids[2], reps: 5, kg: 999, now: t0)

        let entries = f.lib.snapshot(of: session).entries
        #expect(entries.map(\.actualReps) == [100, 1, 5])
        #expect(entries.map(\.actualKg) == [62.5, 0, 500])
    }

    @Test func doneWhileRestingDoesNothing() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        try f.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0)
        let before = f.lib.snapshot(of: session)
        try f.lib.completeSet(in: session, setID: ids[1], reps: 8, kg: 62.5, now: t0 + 10)
        try f.lib.skipSet(in: session, setID: ids[1], now: t0 + 10)
        #expect(f.lib.snapshot(of: session) == before)
    }

    // MARK: Skip set

    @Test func skipSetOpensTheNextSetWithoutRestAndStampsCompletedAt() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        try f.lib.skipSet(in: session, setID: ids[0], now: t0 + 20)

        let snapshot = f.lib.snapshot(of: session)
        #expect(snapshot.entries[0].status == .skipped)
        #expect(snapshot.entries[0].completedAt == t0 + 20)
        #expect(snapshot.entries[0].actualReps == nil)
        #expect(snapshot.entries[0].actualKg == nil)
        #expect(session.restEndsAt == nil)
        #expect(snapshot.screen(now: t0 + 20) == .set(1))
        try expectPersisted(f, session)
    }

    @Test func skippingTheLastSetFinishesTheWorkout() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        try f.lib.skipSet(in: session, setID: ids[0], now: t0 + 1)
        try f.lib.skipSet(in: session, setID: ids[1], now: t0 + 2)
        try f.lib.skipSet(in: session, setID: ids[2], now: t0 + 3)

        let snapshot = f.lib.snapshot(of: session)
        #expect(session.endedAt == t0 + 3)
        #expect(session.pausedAt == nil)
        #expect(session.restEndsAt == nil)
        #expect(!snapshot.hasDoneSet)
        #expect(snapshot.screen(now: t0 + 100) == .summary)
        try expectPersisted(f, session)
    }

    @Test func finishingAfterAnExpiredRestLeavesNoRest() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        try f.lib.skipSet(in: session, setID: ids[0], now: t0 + 1)
        try f.lib.skipSet(in: session, setID: ids[1], now: t0 + 2)
        // Leftover from bad data: an expired rest. It's cleared before the action and again at the end.
        session.restEndsAt = t0 + 3
        try f.context.save()
        try f.lib.completeSet(in: session, setID: ids[2], reps: 5, kg: 100, now: t0 + 10)
        #expect(session.endedAt == t0 + 10)
        #expect(session.restEndsAt == nil)
        #expect(session.pausedAt == nil)
    }

    // MARK: Skip rest, undo

    @Test func skipRestOpensTheNextSet() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        try f.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0)
        try f.lib.skipRest(in: session, now: t0 + 5)
        #expect(session.restEndsAt == nil)
        #expect(f.lib.snapshot(of: session).screen(now: t0 + 5) == .set(1))
        try expectPersisted(f, session)
    }

    @Test func undoReturnsToPendingAndKeepsActualValues() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        try f.lib.completeSet(in: session, setID: ids[0], reps: 12, kg: 65, now: t0 + 10)
        try f.lib.undo(in: session, setID: ids[0], now: t0 + 20)

        let snapshot = f.lib.snapshot(of: session)
        let a = snapshot.entries[0]
        #expect(a.status == .pending)
        #expect(a.completedAt == nil)
        #expect(a.actualReps == 12)
        #expect(a.actualKg == 65)
        #expect(session.restEndsAt == nil)
        #expect(snapshot.screen(now: t0 + 20) == .set(0))
        #expect(snapshot.prefill(forSetAt: 0) == (12, 65))
        try expectPersisted(f, session)
    }

    @Test func undoAfterTheRestExpiredDoesNothing() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        try f.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0)
        try f.lib.undo(in: session, setID: ids[0], now: t0 + 90)

        let snapshot = f.lib.snapshot(of: session)
        #expect(snapshot.entries[0].status == .done)
        #expect(snapshot.entries[0].completedAt == t0)
        #expect(session.restEndsAt == nil)  // The expired rest was cleared.
    }

    @Test func undoWithAWrongOrStaleIDChangesNothing() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        try f.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0)
        let before = f.lib.snapshot(of: session)
        try f.lib.undo(in: session, setID: ids[1], now: t0 + 5)
        try f.lib.undo(in: session, setID: UUID(), now: t0 + 5)
        #expect(f.lib.snapshot(of: session) == before)
    }

    @Test func undoOnTheSetScreenDoesNothing() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        let before = f.lib.snapshot(of: session)
        try f.lib.undo(in: session, setID: ids[0], now: t0 + 5)
        #expect(f.lib.snapshot(of: session) == before)
    }

    @Test func undoThenSkipLeavesNoActualValues() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        try f.lib.completeSet(in: session, setID: ids[0], reps: 12, kg: 65, now: t0 + 10)
        try f.lib.undo(in: session, setID: ids[0], now: t0 + 20)
        try f.lib.skipSet(in: session, setID: ids[0], now: t0 + 30)

        let a = f.lib.snapshot(of: session).entries[0]
        #expect(a.status == .skipped)
        #expect(a.actualReps == nil)
        #expect(a.actualKg == nil)
        #expect(a.completedAt == t0 + 30)
        try expectPersisted(f, session)
    }

    // MARK: Stale IDs

    @Test func secondDoneWithAStaleIDChangesNothing() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        try f.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0)
        try f.lib.skipRest(in: session, now: t0 + 1)
        try f.lib.completeSet(in: session, setID: ids[1], reps: 8, kg: 62.5, now: t0 + 2)
        // Set B had no rest, so C is now current: a double tap on B's Done must not touch C.
        let before = f.lib.snapshot(of: session)
        try f.lib.completeSet(in: session, setID: ids[1], reps: 9, kg: 70, now: t0 + 3)
        try f.lib.skipSet(in: session, setID: ids[1], now: t0 + 3)
        #expect(f.lib.snapshot(of: session) == before)
        #expect(before.entries[2].status == .pending)
    }

    @Test func staleDoneAndSkipAfterARestingSetChangeNothing() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        try f.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0)
        // The rest has expired, so B is current; a late tap for A does nothing.
        let before = f.lib.snapshot(of: session)
        try f.lib.completeSet(in: session, setID: ids[0], reps: 11, kg: 61, now: t0 + 100)
        try f.lib.skipSet(in: session, setID: ids[0], now: t0 + 100)
        var expected = before
        expected.restEndsAt = nil  // Only the expired rest is cleared.
        #expect(f.lib.snapshot(of: session) == expected)
    }

    @Test func skipWithAStaleIDChangesNothing() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        try f.lib.skipSet(in: session, setID: ids[0], now: t0 + 1)
        let before = f.lib.snapshot(of: session)
        try f.lib.skipSet(in: session, setID: ids[0], now: t0 + 2)
        try f.lib.skipSet(in: session, setID: UUID(), now: t0 + 2)
        #expect(f.lib.snapshot(of: session) == before)
    }

    // MARK: Expired rest

    @Test func anExpiredRestIsClearedByTheNextAction() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        try f.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0)
        #expect(session.restEndsAt == t0 + 90)
        try f.lib.skipSet(in: session, setID: ids[1], now: t0 + 100)
        #expect(session.restEndsAt == nil)
        #expect(f.lib.snapshot(of: session).entries[1].status == .skipped)
    }

    @Test func finishRestClearsOnlyAnExpiredRest() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        try f.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0)
        try f.lib.finishRest(in: session, now: t0 + 89)
        #expect(session.restEndsAt == t0 + 90)
        try f.lib.finishRest(in: session, now: t0 + 90)
        #expect(session.restEndsAt == nil)
        #expect(f.lib.snapshot(of: session).screen(now: t0 + 90) == .set(1))
        try expectPersisted(f, session)
    }

    // MARK: Finished and paused

    @Test func finishRestWhilePaused() throws {
        // Rest ends at t0 + 90. Paused after it ended: the expired rest is cleared.
        let expired = try makeFixture()
        let (s1, ids1) = try started(expired)
        try expired.lib.completeSet(in: s1, setID: ids1[0], reps: 10, kg: 60, now: t0)
        #expect(s1.restEndsAt == t0 + 90)
        s1.pausedAt = t0 + 100
        try expired.context.save()
        try expired.lib.finishRest(in: s1, now: t0 + 200)
        #expect(s1.restEndsAt == nil)

        // Paused before it ended: the rest is frozen and stays.
        let running = try makeFixture()
        let (s2, ids2) = try started(running)
        try running.lib.completeSet(in: s2, setID: ids2[0], reps: 10, kg: 60, now: t0)
        s2.pausedAt = t0 + 30
        try running.context.save()
        try running.lib.finishRest(in: s2, now: t0 + 200)
        #expect(s2.restEndsAt == t0 + 90)
    }

    @Test func actionsOnAFinishedSessionDoNothing() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        try completeAll(f, session, ids, start: t0)
        let before = f.lib.snapshot(of: session)
        for id in ids {
            try f.lib.completeSet(in: session, setID: id, reps: 1, kg: 1, now: t0 + 500)
            try f.lib.skipSet(in: session, setID: id, now: t0 + 500)
            try f.lib.undo(in: session, setID: id, now: t0 + 500)
        }
        try f.lib.skipRest(in: session, now: t0 + 500)
        try f.lib.finishRest(in: session, now: t0 + 500)
        #expect(f.lib.snapshot(of: session) == before)
    }

    @Test func setActionsDoNothingWhilePaused() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        session.pausedAt = t0 + 5
        try f.context.save()
        let before = f.lib.snapshot(of: session)
        try f.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0 + 10)
        try f.lib.skipSet(in: session, setID: ids[0], now: t0 + 10)
        #expect(f.lib.snapshot(of: session) == before)

        // A rest paused part way through can't be skipped or undone from outside either.
        session.pausedAt = nil
        try f.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0 + 20)
        session.pausedAt = t0 + 30
        try f.context.save()
        let resting = f.lib.snapshot(of: session)
        try f.lib.skipRest(in: session, now: t0 + 40)
        try f.lib.undo(in: session, setID: ids[0], now: t0 + 40)
        #expect(f.lib.snapshot(of: session) == resting)
    }

    // MARK: Persistence

    @Test func everyActionIsSavedAndReadsBackFromAFreshContext() throws {
        let f = try makeFixture()
        let (session, ids) = try started(f)
        try expectPersisted(f, session)
        try f.lib.completeSet(in: session, setID: ids[0], reps: 11, kg: 62.5, now: t0 + 10)
        try expectPersisted(f, session)
        try f.lib.undo(in: session, setID: ids[0], now: t0 + 12)
        try expectPersisted(f, session)
        try f.lib.skipSet(in: session, setID: ids[0], now: t0 + 14)
        try expectPersisted(f, session)
        try f.lib.completeSet(in: session, setID: ids[1], reps: 8, kg: 62.5, now: t0 + 20)
        try expectPersisted(f, session)
        try f.lib.completeSet(in: session, setID: ids[2], reps: 5, kg: 100, now: t0 + 30)
        try expectPersisted(f, session)
        #expect(!f.context.hasChanges)
    }
}
