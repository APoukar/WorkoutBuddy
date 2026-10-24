import Foundation
import SwiftData
import Testing
@testable import WorkoutBuddy

struct SchemaV1Tests {
    /// Inserts children in scrambled order so sorting is actually exercised.
    private func makeGraph(in context: ModelContext) -> (Workout, WorkoutSession, Exercise) {
        let bench = Exercise(name: "Bench Press", muscleGroup: .chest)
        let squat = Exercise(name: "Back Squat", muscleGroup: .legs)
        context.insert(bench)
        context.insert(squat)

        let workout = Workout(name: "Push")
        context.insert(workout)
        for order in [2, 0, 1] {
            let we = WorkoutExercise(order: order, exercise: order == 1 ? squat : bench)
            workout.exercises.append(we)
            for setOrder in [1, 2, 0] {
                we.sets.append(PlannedSet(order: setOrder, reps: 10, kg: 20, restSeconds: 90))
            }
        }

        let session = WorkoutSession(workout: workout)
        context.insert(session)
        for order in [1, 0] {
            let se = SessionExercise(order: order, exercise: bench)
            session.exercises.append(se)
            for setOrder in [2, 0, 1] {
                se.sets.append(SessionSet(order: setOrder, plannedReps: 10, plannedKg: 20, plannedRestSeconds: 90))
            }
        }
        return (workout, session, bench)
    }

    @Test func sortedAccessorsFollowOrder() throws {
        let t = try TestContainer()
        let (workout, session, _) = makeGraph(in: t.context)
        try t.context.save()

        #expect(workout.orderedExercises.map(\.order) == [0, 1, 2])
        for we in workout.orderedExercises {
            #expect(we.orderedSets.map(\.order) == [0, 1, 2])
        }
        #expect(session.orderedExercises.map(\.order) == [0, 1])
        for se in session.orderedExercises {
            #expect(se.orderedSets.map(\.order) == [0, 1, 2])
        }
    }

    @Test func deletingWorkoutCascadesAndKeepsExercise() throws {
        let t = try TestContainer()
        let (workout, _, _) = makeGraph(in: t.context)
        try t.context.save()

        t.context.delete(workout)
        try t.context.save()

        #expect(try t.context.fetchCount(FetchDescriptor<Workout>()) == 0)
        #expect(try t.context.fetchCount(FetchDescriptor<WorkoutExercise>()) == 0)
        #expect(try t.context.fetchCount(FetchDescriptor<PlannedSet>()) == 0)
        #expect(try t.context.fetchCount(FetchDescriptor<Exercise>()) == 2)
        // Sessions are nullified, not deleted.
        let sessions = try t.context.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.workout == nil)
        #expect(try t.context.fetchCount(FetchDescriptor<SessionSet>()) == 6)
    }

    @Test func deletingSessionCascadesToItsChildren() throws {
        let t = try TestContainer()
        let (workout, session, _) = makeGraph(in: t.context)
        try t.context.save()

        t.context.delete(session)
        try t.context.save()

        #expect(try t.context.fetchCount(FetchDescriptor<SessionExercise>()) == 0)
        #expect(try t.context.fetchCount(FetchDescriptor<SessionSet>()) == 0)
        #expect(try t.context.fetchCount(FetchDescriptor<Exercise>()) == 2)
        #expect(workout.sessions.isEmpty)
    }

    @Test func deletingSingleChildrenRemovesThemAndTheyStayGone() throws {
        let t = try TestContainer()
        let (workout, session, _) = makeGraph(in: t.context)
        try t.context.save()
        #expect(try t.context.fetchCount(FetchDescriptor<WorkoutExercise>()) == 3)
        #expect(try t.context.fetchCount(FetchDescriptor<PlannedSet>()) == 9)

        // Delete one WorkoutExercise (cascades to its 3 sets) and one PlannedSet of another.
        let removedExercise = workout.orderedExercises[0]
        let keptExercise = workout.orderedExercises[1]
        t.context.delete(removedExercise)
        t.context.delete(keptExercise.orderedSets[0])
        try t.context.save()

        #expect(workout.orderedExercises.map(\.order) == [1, 2])
        #expect(keptExercise.orderedSets.map(\.order) == [1, 2])
        #expect(try t.context.fetchCount(FetchDescriptor<WorkoutExercise>()) == 2)
        #expect(try t.context.fetchCount(FetchDescriptor<PlannedSet>()) == 5)

        // A further delete and save must not bring anything back.
        t.context.delete(workout.orderedExercises[0])
        try t.context.save()
        #expect(workout.orderedExercises.count == 1)
        #expect(try t.context.fetchCount(FetchDescriptor<WorkoutExercise>()) == 1)
        #expect(try t.context.fetchCount(FetchDescriptor<PlannedSet>()) == 3)

        // Appending after a delete must not resurrect the deleted items.
        let survivorID = workout.orderedExercises[0].id
        let added = WorkoutExercise(order: 3, exercise: nil)
        workout.exercises.append(added)
        try t.context.save()
        #expect(workout.orderedExercises.map(\.id) == [survivorID, added.id])
        #expect(try t.context.fetchCount(FetchDescriptor<WorkoutExercise>()) == 2)
        #expect(try t.context.fetchCount(FetchDescriptor<PlannedSet>()) == 3)

        // Same for a SessionSet.
        let sessionExercise = session.orderedExercises[0]
        t.context.delete(sessionExercise.orderedSets[1])
        try t.context.save()
        #expect(sessionExercise.orderedSets.map(\.order) == [0, 2])
        #expect(try t.context.fetchCount(FetchDescriptor<SessionSet>()) == 5)

        t.context.delete(sessionExercise.orderedSets[0])
        try t.context.save()
        #expect(sessionExercise.orderedSets.map(\.order) == [2])
        #expect(try t.context.fetchCount(FetchDescriptor<SessionSet>()) == 4)
    }

    @Test func workoutSessionsIsInverseOfSessionWorkout() throws {
        let t = try TestContainer()
        let (workout, session, _) = makeGraph(in: t.context)
        let second = WorkoutSession(workout: workout)
        t.context.insert(second)
        try t.context.save()

        let ids = Set(workout.sessions.map(\.id))
        #expect(ids == [session.id, second.id])
    }

    @Test func rawValuesConvertToEnumCases() throws {
        let t = try TestContainer()
        let exercise = Exercise(name: "Curl", muscleGroup: .biceps)
        let session = WorkoutSession(workout: nil, status: .endedEarly)
        let set = SessionSet(order: 0, plannedReps: 5, plannedKg: 10, plannedRestSeconds: 60, status: .notPerformed)
        t.context.insert(exercise)
        t.context.insert(session)
        t.context.insert(set)
        try t.context.save()

        #expect(exercise.muscleGroupRaw == "biceps")
        #expect(exercise.muscleGroup == .biceps)
        #expect(session.statusRaw == "endedEarly")
        #expect(session.status == .endedEarly)
        #expect(set.statusRaw == "notPerformed")
        #expect(set.status == .notPerformed)

        exercise.muscleGroup = .fullBody
        session.status = .completed
        set.status = .done
        #expect(exercise.muscleGroupRaw == "fullBody")
        #expect(session.statusRaw == "completed")
        #expect(set.statusRaw == "done")

        for group in MuscleGroup.allCases { #expect(MuscleGroup(rawValue: group.rawValue) == group) }
        for status in SessionStatus.allCases { #expect(SessionStatus(rawValue: status.rawValue) == status) }
        for status in SetStatus.allCases { #expect(SetStatus(rawValue: status.rawValue) == status) }
    }

    @Test func idLookupFindsArchivedAndSoftDeletedRecords() throws {
        let t = try TestContainer()
        let exercise = Exercise(name: "Old", muscleGroup: .core, isArchived: true)
        let workout = Workout(name: "Gone", isSoftDeleted: true)
        t.context.insert(exercise)
        t.context.insert(workout)
        try t.context.save()

        let exerciseID = exercise.id
        let workoutID = workout.id
        #expect(try t.context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == exerciseID })).count == 1)
        #expect(try t.context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.id == workoutID })).count == 1)
        #expect(try t.context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { !$0.isArchived })).isEmpty)
    }

    @Test func displayNamesAreNonEmptyAndMuscleGroupOrderMatchesSpec() {
        #expect(MuscleGroup.allCases.map(\.displayName) ==
            ["Chest", "Back", "Shoulders", "Biceps", "Triceps", "Legs", "Glutes", "Core", "Full body"])
        #expect(SessionStatus.allCases.allSatisfy { !$0.displayName.isEmpty })
        #expect(SetStatus.allCases.allSatisfy { !$0.displayName.isEmpty })
    }
}
