import Foundation
import SwiftData
import Testing
@testable import WorkoutBuddy

/// A store with the "Push Day" template, shared by the `SessionLibrary` tests:
/// Bench Press: A (10 x 60, rest 90), B (8 x 62.5, rest 0). Back Squat: C (5 x 100, rest 120).
@MainActor
struct SessionFixture {
    static let t0 = Date(timeIntervalSince1970: 1_000_000)
    static let setA = SetValues(reps: 10, kg: 60, restSeconds: 90)
    static let setB = SetValues(reps: 8, kg: 62.5, restSeconds: 0)
    static let setC = SetValues(reps: 5, kg: 100, restSeconds: 120)

    let tc: TestContainer
    let lib: SessionLibrary
    let bench: Exercise
    let squat: Exercise
    let workout: Workout
    var context: ModelContext { tc.context }

    /// Creates the exercises and the template (created at `t0`). No session is started.
    static func make() throws -> SessionFixture {
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
        return SessionFixture(tc: tc, lib: SessionLibrary(context: tc.context), bench: bench, squat: squat, workout: workout)
    }

    /// Starts a session of the template, returning it with its set IDs in order (A, B, C).
    func start(at now: Date = SessionFixture.t0) throws -> (WorkoutSession, [UUID]) {
        let session = try lib.start(workout, now: now)
        return (session, lib.snapshot(of: session).entries.map(\.id))
    }

    /// Whether what's in the store (read through a fresh context) equals the session's snapshot.
    func expectPersisted(_ session: WorkoutSession, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let fresh = ModelContext(tc.container)
        let sessionID = session.id
        let fetched = try fresh.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID }))
        let reloaded = try #require(fetched.first, sourceLocation: sourceLocation)
        #expect(
            SessionLibrary(context: fresh).snapshot(of: reloaded) == lib.snapshot(of: session),
            sourceLocation: sourceLocation)
        #expect(reloaded.status == session.status, sourceLocation: sourceLocation)
    }
}

extension SessionSnapshot {
    /// The snapshot without `lastActionAt`, for tests that check an action changed nothing else:
    /// every action that reaches `SessionLibrary.perform` stamps the last action, even when it's a no-op.
    func ignoringLastAction() -> SessionSnapshot {
        var copy = self
        copy.lastActionAt = nil
        return copy
    }
}
