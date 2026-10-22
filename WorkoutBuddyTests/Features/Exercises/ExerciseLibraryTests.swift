import Foundation
import SwiftData
import Testing
@testable import WorkoutBuddy

@MainActor
struct ExerciseLibraryTests {
    private func makeWorkout(_ name: String, exercises: [Exercise], in context: ModelContext, deleted: Bool = false) -> Workout {
        let workout = Workout(name: name, isSoftDeleted: deleted)
        context.insert(workout)
        for (index, exercise) in exercises.enumerated() {
            let row = WorkoutExercise(order: index, exercise: exercise)
            row.workout = workout
            context.insert(row)
            let set = PlannedSet(order: 0, reps: 10, kg: 20, restSeconds: 90)
            set.workoutExercise = row
            context.insert(set)
        }
        return workout
    }

    @Test func addRenameAndRegroup() throws {
        let tc = try TestContainer()
        let lib = ExerciseLibrary(context: tc.context)
        let e = try lib.add(name: "  Cable Fly  ", muscleGroup: .chest)
        #expect(e.name == "Cable Fly" && e.isCustom && e.muscleGroup == .chest)
        try lib.update(e, name: "Cable Crossover", muscleGroup: .chest)
        #expect(e.name == "Cable Crossover")
        try lib.update(e, name: "Cable Crossover", muscleGroup: .shoulders)
        #expect(e.muscleGroup == .shoulders)
        #expect(lib.exercise(id: e.id) === e)
    }

    @Test func emptyAndWhitespaceNamesRejected() throws {
        let tc = try TestContainer()
        let lib = ExerciseLibrary(context: tc.context)
        #expect(lib.validate(name: "") == .empty)
        #expect(lib.validate(name: "  \n ") == .empty)
        #expect(throws: ExerciseNameError.empty) { try lib.add(name: " ", muscleGroup: .core) }
    }

    @Test func duplicatesDifferingInCaseRejected() throws {
        let tc = try TestContainer()
        let lib = ExerciseLibrary(context: tc.context)
        try lib.add(name: "Bench Press", muscleGroup: .chest)
        #expect(lib.validate(name: "bench press") == .duplicate)
        #expect(lib.validate(name: " BENCH PRESS ") == .duplicate)
        #expect(throws: ExerciseNameError.duplicate) { try lib.add(name: "bench PRESS", muscleGroup: .chest) }
        let other = try lib.add(name: "Squat", muscleGroup: .legs)
        #expect(throws: ExerciseNameError.duplicate) { try lib.update(other, name: "bench press", muscleGroup: .legs) }
        #expect(other.name == "Squat")
    }

    @Test func archivedNameCanBeReused() throws {
        let tc = try TestContainer()
        let lib = ExerciseLibrary(context: tc.context)
        let old = try lib.add(name: "Bench Press", muscleGroup: .chest)
        try lib.archive(old)
        #expect(lib.validate(name: "Bench Press") == nil)
        let new = try lib.add(name: "Bench Press", muscleGroup: .chest)
        #expect(new.id != old.id)
    }

    @Test func renameToOwnNameInDifferentCaseAllowed() throws {
        let tc = try TestContainer()
        let lib = ExerciseLibrary(context: tc.context)
        let e = try lib.add(name: "Bench Press", muscleGroup: .chest)
        #expect(lib.validate(name: "bench press", excluding: e) == nil)
        try lib.update(e, name: "bench press", muscleGroup: .chest)
        #expect(e.name == "bench press")
    }

    @Test func updateChangesNameAndGroupTogether() throws {
        let tc = try TestContainer()
        let lib = ExerciseLibrary(context: tc.context)
        let e = try lib.add(name: "Fly", muscleGroup: .chest)
        try lib.update(e, name: "  Cable Fly ", muscleGroup: .shoulders)
        #expect(e.name == "Cable Fly" && e.muscleGroup == .shoulders)
    }

    @Test func updateOnlyCaseChangeAndOnlyGroup() throws {
        let tc = try TestContainer()
        let lib = ExerciseLibrary(context: tc.context)
        let e = try lib.add(name: "Bench Press", muscleGroup: .chest)
        try lib.update(e, name: "bench press", muscleGroup: .chest)
        #expect(e.name == "bench press")
        try lib.update(e, name: "bench press", muscleGroup: .triceps)
        #expect(e.name == "bench press" && e.muscleGroup == .triceps)
    }

    @Test func updateDuplicateThrowsAndChangesNothing() throws {
        let tc = try TestContainer()
        let lib = ExerciseLibrary(context: tc.context)
        try lib.add(name: "Bench Press", muscleGroup: .chest)
        let other = try lib.add(name: "Squat", muscleGroup: .legs)
        #expect(throws: ExerciseNameError.duplicate) { try lib.update(other, name: "BENCH press", muscleGroup: .core) }
        #expect(throws: ExerciseNameError.empty) { try lib.update(other, name: "  ", muscleGroup: .core) }
        #expect(other.name == "Squat" && other.muscleGroup == .legs)
    }

    @Test func archiveHidesFromActiveFetchButIDLookupFinds() throws {
        let tc = try TestContainer()
        let lib = ExerciseLibrary(context: tc.context)
        let e = try lib.add(name: "Curl", muscleGroup: .biceps)
        try lib.archive(e)
        let active = try tc.context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { !$0.isArchived }))
        #expect(active.isEmpty)
        #expect(lib.exercise(id: e.id)?.isArchived == true)
        #expect(lib.exercise(id: UUID()) == nil)
    }

    @Test func archiveRemovesFromTemplatesRenumbersAndKeepsSessions() throws {
        let tc = try TestContainer()
        let ctx = tc.context
        let lib = ExerciseLibrary(context: ctx)
        let a = try lib.add(name: "A", muscleGroup: .chest)
        let b = try lib.add(name: "B", muscleGroup: .chest)
        let c = try lib.add(name: "C", muscleGroup: .chest)
        let active = makeWorkout("Active", exercises: [a, b, c], in: ctx)
        let hidden = makeWorkout("Hidden", exercises: [b, a], in: ctx, deleted: true)

        let session = WorkoutSession(workout: active)
        ctx.insert(session)
        let se = SessionExercise(order: 0, exercise: b)
        se.session = session
        ctx.insert(se)
        let ss = SessionSet(order: 0, plannedReps: 10, plannedKg: 20, plannedRestSeconds: 90)
        ss.sessionExercise = se
        ctx.insert(ss)
        try ctx.save()

        try lib.archive(b)

        #expect(active.orderedExercises.compactMap { $0.exercise?.name } == ["A", "C"])
        #expect(active.orderedExercises.map(\.order) == [0, 1])
        #expect(hidden.orderedExercises.compactMap { $0.exercise?.name } == ["A"])
        #expect(hidden.orderedExercises.map(\.order) == [0])
        // 3 + 2 rows before; 2 + 1 after, and planned sets of removed rows are gone.
        #expect(try ctx.fetchCount(FetchDescriptor<WorkoutExercise>()) == 3)
        #expect(try ctx.fetchCount(FetchDescriptor<PlannedSet>()) == 3)
        // Session untouched.
        #expect(session.orderedExercises.count == 1)
        #expect(session.orderedExercises[0].exercise?.id == b.id)
        #expect(session.orderedExercises[0].orderedSets.count == 1)
        #expect(try ctx.fetchCount(FetchDescriptor<SessionSet>()) == 1)
    }

    @Test func workoutsUsingSkipsSoftDeletedAndSortsByName() throws {
        let tc = try TestContainer()
        let ctx = tc.context
        let lib = ExerciseLibrary(context: tc.context)
        let a = try lib.add(name: "A", muscleGroup: .chest)
        let other = try lib.add(name: "Other", muscleGroup: .chest)
        _ = makeWorkout("Zed", exercises: [a], in: ctx)
        _ = makeWorkout("Alpha", exercises: [other, a], in: ctx)
        _ = makeWorkout("Gone", exercises: [a], in: ctx, deleted: true)
        _ = makeWorkout("Unrelated", exercises: [other], in: ctx)
        try ctx.save()
        #expect(try lib.workoutsUsing(a).map(\.name) == ["Alpha", "Zed"])
    }

    @Test func deletionWarningFromLibraryFlagsEmptiedTemplates() throws {
        let tc = try TestContainer()
        let ctx = tc.context
        let lib = ExerciseLibrary(context: ctx)
        let a = try lib.add(name: "A", muscleGroup: .chest)
        let b = try lib.add(name: "B", muscleGroup: .chest)
        _ = makeWorkout("Solo", exercises: [a], in: ctx)
        _ = makeWorkout("Mixed", exercises: [a, b], in: ctx)
        try ctx.save()
        let warning = try lib.deletionWarning(for: a)
        #expect(warning == .make(exerciseName: "A", templateNames: ["Mixed", "Solo"], emptiedTemplateNames: ["Solo"]))
    }

    @Test func duplicateRowsInOneTemplateAreAllRemovedAndRenumbered() throws {
        let tc = try TestContainer()
        let ctx = tc.context
        let lib = ExerciseLibrary(context: ctx)
        let a = try lib.add(name: "A", muscleGroup: .chest)
        let b = try lib.add(name: "B", muscleGroup: .chest)
        let w = makeWorkout("W", exercises: [a, b, a], in: ctx)
        try ctx.save()
        #expect(try lib.deletionWarning(for: a)
            == .make(exerciseName: "A", templateNames: ["W"], emptiedTemplateNames: []))
        try lib.archive(a)
        #expect(w.orderedExercises.count == 1)
        #expect(w.orderedExercises[0].exercise?.id == b.id)
        #expect(w.orderedExercises[0].order == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<WorkoutExercise>()) == 1)
    }

    @Test func templateOfOnlyThisExerciseIsFlaggedAndSurvivesEmpty() throws {
        let tc = try TestContainer()
        let ctx = tc.context
        let lib = ExerciseLibrary(context: ctx)
        let a = try lib.add(name: "A", muscleGroup: .chest)
        let w = makeWorkout("W", exercises: [a, a], in: ctx)
        try ctx.save()
        #expect(try lib.deletionWarning(for: a)
            == .make(exerciseName: "A", templateNames: ["W"], emptiedTemplateNames: ["W"]))
        try lib.archive(a)
        #expect(!w.isSoftDeleted)
        #expect(w.orderedExercises.isEmpty)
        #expect(try ctx.fetchCount(FetchDescriptor<Workout>()) == 1)
        #expect(try ctx.fetchCount(FetchDescriptor<PlannedSet>()) == 0)
    }
}
