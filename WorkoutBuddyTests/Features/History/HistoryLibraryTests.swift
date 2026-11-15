import Foundation
import SwiftData
import Testing
@testable import WorkoutBuddy

@MainActor
struct HistoryLibraryTests {
    private let t0 = SessionFixture.t0
    private let day: TimeInterval = 86_400

    private func history(_ f: SessionFixture) -> HistoryLibrary { HistoryLibrary(context: f.context) }

    /// Starts at `start`, does all three sets and saves. Finished at `start + 30`.
    @discardableResult
    private func savedSession(_ f: SessionFixture, at start: Date, doAll: Bool = true) throws -> WorkoutSession {
        let (session, ids) = try f.start(at: start)
        try f.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: start + 10)
        try f.lib.skipRest(in: session, now: start + 11)
        if doAll {
            try f.lib.completeSet(in: session, setID: ids[1], reps: 8, kg: 62.5, now: start + 20)
            try f.lib.completeSet(in: session, setID: ids[2], reps: 5, kg: 100, now: start + 30)
        } else {
            try f.lib.endEarly(in: session, now: start + 20)
        }
        try f.lib.save(session)
        return session
    }

    private func count<T: PersistentModel>(_ type: T.Type, _ f: SessionFixture) throws -> Int {
        try f.context.fetchCount(FetchDescriptor<T>())
    }

    @Test func finishedSessionsIncludeCompletedAndEndedEarlyOldestFirst() throws {
        let f = try SessionFixture.make()
        let second = try savedSession(f, at: t0 + 2 * day, doAll: false)
        let first = try savedSession(f, at: t0 + day)
        #expect(first.status == .completed)
        #expect(second.status == .endedEarly)
        let result = try history(f).finishedSessions()
        #expect(result.map(\.id) == [first.id, second.id])
    }

    @Test func runningAndWaitingForSaveSessionsAreExcluded() throws {
        let f = try SessionFixture.make()
        let saved = try savedSession(f, at: t0 + day)

        // Waiting for Save: finished but still in progress.
        let (waiting, ids) = try f.start(at: t0 + 2 * day)
        try f.lib.completeSet(in: waiting, setID: ids[0], reps: 10, kg: 60, now: t0 + 2 * day + 10)
        try f.lib.skipRest(in: waiting, now: t0 + 2 * day + 11)
        try f.lib.endEarly(in: waiting, now: t0 + 2 * day + 20)
        #expect(waiting.status == .inProgress)
        #expect(try history(f).finishedSessions().map(\.id) == [saved.id])

        try f.lib.discard(waiting)
        // Running.
        let (running, _) = try f.start(at: t0 + 3 * day)
        #expect(running.status == .inProgress)
        #expect(try history(f).finishedSessions().map(\.id) == [saved.id])
    }

    @Test func sessionsOfASoftDeletedTemplateAndWithAnArchivedExerciseStayInHistory() throws {
        let f = try SessionFixture.make()
        let saved = try savedSession(f, at: t0 + day)
        try WorkoutLibrary(context: f.context).softDelete(f.workout)
        try ExerciseLibrary(context: f.context).archive(f.bench)

        let result = try history(f).finishedSessions()
        #expect(result.map(\.id) == [saved.id])
        #expect(result[0].workout?.name == "Push Day")
        #expect(f.lib.exerciseNames(of: result[0]).values.contains("Bench Press"))
    }

    @Test func lookupByIDHasNoStatusFilter() throws {
        let f = try SessionFixture.make()
        let saved = try savedSession(f, at: t0 + day)
        let (running, _) = try f.start(at: t0 + 2 * day)
        try WorkoutLibrary(context: f.context).softDelete(f.workout)

        #expect(history(f).session(id: saved.id)?.id == saved.id)
        #expect(history(f).session(id: running.id)?.id == running.id)
        #expect(history(f).session(id: UUID()) == nil)
    }

    @Test func deleteRemovesTheSessionWithItsExercisesAndSetsOnly() throws {
        let f = try SessionFixture.make()
        let keep = try savedSession(f, at: t0 + day)
        let gone = try savedSession(f, at: t0 + 2 * day)
        #expect(try count(WorkoutSession.self, f) == 2)
        #expect(try count(SessionExercise.self, f) == 4)
        #expect(try count(SessionSet.self, f) == 6)

        try history(f).delete(gone)

        #expect(try history(f).finishedSessions().map(\.id) == [keep.id])
        #expect(try count(SessionExercise.self, f) == 2)
        #expect(try count(SessionSet.self, f) == 3)
        #expect(try count(Workout.self, f) == 1)
        #expect(try count(Exercise.self, f) == 2)
        #expect(history(f).session(id: gone.id) == nil)
        // Persisted: a fresh context agrees.
        let fresh = ModelContext(f.tc.container)
        #expect(try HistoryLibrary(context: fresh).finishedSessions().map(\.id) == [keep.id])
    }

    @Test func deleteWorksOnAnEndedEarlySessionOfASoftDeletedTemplate() throws {
        let f = try SessionFixture.make()
        let early = try savedSession(f, at: t0 + day, doAll: false)
        try WorkoutLibrary(context: f.context).softDelete(f.workout)
        try history(f).delete(early)
        #expect(try count(WorkoutSession.self, f) == 0)
    }

    @Test func deleteDoesNothingOnASessionInProgress() throws {
        let f = try SessionFixture.make()
        let (running, _) = try f.start(at: t0 + day)
        try history(f).delete(running)
        #expect(history(f).session(id: running.id) != nil)
        #expect(try count(SessionSet.self, f) == 3)
    }

    @Test func lastPerformedFallsBackToThePreviousSessionAfterADelete() throws {
        let f = try SessionFixture.make()
        let older = try savedSession(f, at: t0 + day)
        let newer = try savedSession(f, at: t0 + 2 * day)
        let workouts = WorkoutLibrary(context: f.context)
        #expect(workouts.lastPerformed(f.workout) == newer.startedAt)

        try history(f).delete(newer)
        #expect(workouts.lastPerformed(f.workout) == older.startedAt)

        try history(f).delete(older)
        #expect(workouts.lastPerformed(f.workout) == nil)
    }
}
