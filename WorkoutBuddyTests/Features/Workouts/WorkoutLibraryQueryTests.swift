import Foundation
import SwiftData
import Testing
@testable import WorkoutBuddy

@MainActor
struct WorkoutLibraryQueryTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t1 = Date(timeIntervalSince1970: 2_000_000)
    private let t2 = Date(timeIntervalSince1970: 3_000_000)
    private let t3 = Date(timeIntervalSince1970: 4_000_000)
    private let setA = SetValues(reps: 10, kg: 60, restSeconds: 90)
    private let setB = SetValues(reps: 8, kg: 70, restSeconds: 120)
    private let setC = SetValues(reps: 6, kg: 80, restSeconds: 150)
    private let settings = AppSettings.Values(
        reps: 12, kg: 25, restSeconds: 45, weightStep: .twoAndHalf, soundEnabled: true, hapticsEnabled: true)

    private func makeExercise(_ name: String, in context: ModelContext, defaults: ExerciseDefaults = .none) throws -> Exercise {
        let exercise = Exercise(name: name, muscleGroup: .chest)
        exercise.defaults = defaults
        context.insert(exercise)
        try context.save()
        return exercise
    }

    private func draft(_ name: String, _ exercises: [(Exercise, [SetValues])]) -> WorkoutDraft {
        WorkoutDraft(
            name: name,
            exercises: exercises.map { exercise, sets in
                DraftExercise(exerciseID: exercise.id, sets: sets.map { DraftSet(values: $0) })
            })
    }

    /// Inserts a template directly, so `createdAt`, `updatedAt` and `id` can be chosen freely.
    @discardableResult
    private func insertTemplate(
        _ name: String, exercise: Exercise, sets: [SetValues], id: UUID = UUID(),
        createdAt: Date, updatedAt: Date, in context: ModelContext
    ) throws -> Workout {
        let workout = Workout(id: id, name: name, createdAt: createdAt, updatedAt: updatedAt)
        context.insert(workout)
        let row = WorkoutExercise(order: 0, exercise: exercise)
        context.insert(row)
        row.workout = workout
        for (index, values) in sets.enumerated() {
            let set = PlannedSet(order: index, reps: values.reps, kg: values.kg, restSeconds: values.restSeconds)
            context.insert(set)
            set.workoutExercise = row
        }
        try context.save()
        return workout
    }

    private func addSession(
        to workout: Workout, startedAt: Date, status: SessionStatus, in context: ModelContext
    ) throws {
        let session = WorkoutSession(
            workout: workout, startedAt: startedAt, endedAt: status == .inProgress ? nil : startedAt, status: status)
        context.insert(session)
        try context.save()
    }

    // MARK: lastUsedFirstSet

    @Test func lastUsedIsNilWhenNoTemplateHasTheExercise() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context)
        let press = try makeExercise("Press", in: tc.context)
        #expect(try lib.lastUsedFirstSet(forExerciseID: bench.id) == nil)
        try lib.save(draft("Push", [(press, [setA])]), to: nil, now: t0)
        #expect(try lib.lastUsedFirstSet(forExerciseID: bench.id) == nil)
    }

    @Test func mostRecentlySavedTemplateWins() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context)
        try lib.save(draft("Old", [(bench, [setA])]), to: nil, now: t0)
        try lib.save(draft("New", [(bench, [setB])]), to: nil, now: t1)
        #expect(try lib.lastUsedFirstSet(forExerciseID: bench.id) == setB)
    }

    @Test func aTemplateSavedAgainBecomesTheMostRecent() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context)
        let older = try lib.save(draft("Older", [(bench, [setA])]), to: nil, now: t0)
        try lib.save(draft("Newer", [(bench, [setB])]), to: nil, now: t1)
        #expect(try lib.lastUsedFirstSet(forExerciseID: bench.id) == setB)

        var edited = lib.draft(for: older)
        let row = edited.exercises[0]
        edited.setValues(setC, ofSet: row.sets[0].id, inExercise: row.id)
        try lib.save(edited, to: older, now: t2)
        #expect(try lib.lastUsedFirstSet(forExerciseID: bench.id) == setC)
    }

    @Test func softDeletedTemplatesAreIgnored() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context)
        try lib.save(draft("Old", [(bench, [setA])]), to: nil, now: t0)
        let newer = try lib.save(draft("New", [(bench, [setB])]), to: nil, now: t1)
        try lib.softDelete(newer)
        #expect(try lib.lastUsedFirstSet(forExerciseID: bench.id) == setA)

        let only = try lib.save(draft("Only", [(bench, [setC])]), to: nil, now: t2)
        try lib.softDelete(only)
        let old = try tc.context.fetch(FetchDescriptor<Workout>()).first { $0.name == "Old" }
        try lib.softDelete(#require(old))
        #expect(try lib.lastUsedFirstSet(forExerciseID: bench.id) == nil)
    }

    @Test func takesTheFirstSetByOrder() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context)
        try lib.save(draft("Push", [(bench, [setB, setA, setC])]), to: nil, now: t0)
        #expect(try lib.lastUsedFirstSet(forExerciseID: bench.id) == setB)
    }

    @Test func onlyTheMatchingExercisesRowCounts() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context)
        let press = try makeExercise("Press", in: tc.context)
        try lib.save(draft("Push", [(bench, [setA]), (press, [setB])]), to: nil, now: t0)
        #expect(try lib.lastUsedFirstSet(forExerciseID: press.id) == setB)
        #expect(try lib.lastUsedFirstSet(forExerciseID: bench.id) == setA)
    }

    @Test func aTemplateWhoseRowHasNoSetsIsSkipped() throws {
        let tc = try TestContainer()
        let ctx = tc.context
        let lib = WorkoutLibrary(context: ctx)
        let bench = try makeExercise("Bench", in: ctx)
        try insertTemplate("Older", exercise: bench, sets: [setA], createdAt: t0, updatedAt: t0, in: ctx)
        try insertTemplate("Newer, no sets", exercise: bench, sets: [], createdAt: t1, updatedAt: t1, in: ctx)
        #expect(try lib.lastUsedFirstSet(forExerciseID: bench.id) == setA)
    }

    @Test func tieOnUpdatedAtIsBrokenByLaterCreatedAt() throws {
        let tc = try TestContainer()
        let ctx = tc.context
        let lib = WorkoutLibrary(context: ctx)
        let bench = try makeExercise("Bench", in: ctx)
        try insertTemplate("A", exercise: bench, sets: [setA], createdAt: t0, updatedAt: t2, in: ctx)
        try insertTemplate("B", exercise: bench, sets: [setB], createdAt: t1, updatedAt: t2, in: ctx)
        #expect(try lib.lastUsedFirstSet(forExerciseID: bench.id) == setB)
    }

    @Test(arguments: [true, false])
    func tieOnUpdatedAtAndCreatedAtIsBrokenByGreaterID(insertHighFirst: Bool) throws {
        // A fresh container per insertion order, so the result can't come from fetch order.
        let tc = try TestContainer()
        let ctx = tc.context
        let lib = WorkoutLibrary(context: ctx)
        let bench = try makeExercise("Bench", in: ctx)
        let low = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let high = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let highSet = [setC]
        let lowSet = [setA]
        if insertHighFirst {
            try insertTemplate("High", exercise: bench, sets: highSet, id: high, createdAt: t1, updatedAt: t3, in: ctx)
            try insertTemplate("Low", exercise: bench, sets: lowSet, id: low, createdAt: t1, updatedAt: t3, in: ctx)
        } else {
            try insertTemplate("Low", exercise: bench, sets: lowSet, id: low, createdAt: t1, updatedAt: t3, in: ctx)
            try insertTemplate("High", exercise: bench, sets: highSet, id: high, createdAt: t1, updatedAt: t3, in: ctx)
        }
        #expect(try lib.lastUsedFirstSet(forExerciseID: bench.id) == setC)
    }

    // MARK: firstSetValues

    @Test func firstSetValuesAppliesTheRulePerValue() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context, defaults: ExerciseDefaults(reps: 5, kg: nil, restSeconds: nil))
        // No template yet: reps from the exercise, the rest from Settings.
        #expect(lib.firstSetValues(for: bench, settings: settings) == SetValues(reps: 5, kg: 25, restSeconds: 45))
        // With a saved template: kg and rest from last used.
        try lib.save(draft("Push", [(bench, [setB])]), to: nil, now: t0)
        #expect(lib.firstSetValues(for: bench, settings: settings) == SetValues(reps: 5, kg: 70, restSeconds: 120))
    }

    @Test func firstSetValuesFallsBackToSettingsForANewExercise() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context)
        #expect(lib.firstSetValues(for: bench, settings: settings) == SetValues(reps: 12, kg: 25, restSeconds: 45))
    }

    // MARK: lastPerformed

    @Test func lastPerformedIsNilWithoutSessions() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context)
        let workout = try lib.save(draft("Push", [(bench, [setA])]), to: nil, now: t0)
        #expect(lib.lastPerformed(workout) == nil)
    }

    @Test func lastPerformedPicksTheLatestFinishedSession() throws {
        let tc = try TestContainer()
        let ctx = tc.context
        let lib = WorkoutLibrary(context: ctx)
        let bench = try makeExercise("Bench", in: ctx)
        let workout = try lib.save(draft("Push", [(bench, [setA])]), to: nil, now: t0)
        try addSession(to: workout, startedAt: t1, status: .completed, in: ctx)
        try addSession(to: workout, startedAt: t2, status: .endedEarly, in: ctx)
        try addSession(to: workout, startedAt: t0, status: .completed, in: ctx)
        #expect(lib.lastPerformed(workout) == t2)
    }

    @Test func lastPerformedIgnoresSessionsInProgress() throws {
        let tc = try TestContainer()
        let ctx = tc.context
        let lib = WorkoutLibrary(context: ctx)
        let bench = try makeExercise("Bench", in: ctx)
        let workout = try lib.save(draft("Push", [(bench, [setA])]), to: nil, now: t0)
        try addSession(to: workout, startedAt: t1, status: .completed, in: ctx)
        try addSession(to: workout, startedAt: t3, status: .inProgress, in: ctx)
        #expect(lib.lastPerformed(workout) == t1)

        let other = try lib.save(draft("Pull", [(bench, [setA])]), to: nil, now: t0)
        try addSession(to: other, startedAt: t2, status: .inProgress, in: ctx)
        #expect(lib.lastPerformed(other) == nil)
    }

    // MARK: canStart

    @Test func canStartIsTrueForAValidTemplate() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context)
        let press = try makeExercise("Press", in: tc.context)
        let workout = try lib.save(draft("Push", [(bench, [setA]), (press, [setA, setB])]), to: nil, now: t0)
        #expect(lib.canStart(workout))
    }

    @Test func canStartIsFalseWithoutExercises() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context)
        let workout = try lib.save(draft("Push", [(bench, [setA])]), to: nil, now: t0)
        // Deleting the exercise in Settings removes it from every template.
        try ExerciseLibrary(context: tc.context).archive(bench)
        #expect(workout.exercises.isEmpty)
        #expect(!lib.canStart(workout))
    }

    @Test func canStartIsFalseWhenAnExerciseHasNoSets() throws {
        let tc = try TestContainer()
        let ctx = tc.context
        let lib = WorkoutLibrary(context: ctx)
        let bench = try makeExercise("Bench", in: ctx)
        let press = try makeExercise("Press", in: ctx)
        let workout = try lib.save(draft("Push", [(bench, [setA]), (press, [setB])]), to: nil, now: t0)
        let pressRow = try #require(workout.exercises.first { $0.exercise?.id == press.id })
        for set in pressRow.sets { ctx.delete(set) }
        try ctx.save()
        #expect(!lib.canStart(workout))
    }

    @Test func canStartIgnoresRowsWithoutAnExercise() throws {
        let tc = try TestContainer()
        let ctx = tc.context
        let lib = WorkoutLibrary(context: ctx)
        let bench = try makeExercise("Bench", in: ctx)

        // The only row has no exercise (but has a set): nothing to start.
        let orphan = Workout(name: "Orphan", createdAt: t0)
        ctx.insert(orphan)
        let orphanRow = WorkoutExercise(order: 0, exercise: nil)
        ctx.insert(orphanRow)
        orphanRow.workout = orphan
        let orphanSet = PlannedSet(order: 0, reps: 10, kg: 60, restSeconds: 90)
        ctx.insert(orphanSet)
        orphanSet.workoutExercise = orphanRow
        try ctx.save()
        #expect(!lib.canStart(orphan))

        // A valid row next to an exercise-less row: the exercise-less row is ignored.
        let mixed = try lib.save(draft("Mixed", [(bench, [setA])]), to: nil, now: t0)
        let extra = WorkoutExercise(order: 1, exercise: nil)
        ctx.insert(extra)
        extra.workout = mixed
        try ctx.save()
        #expect(lib.canStart(mixed))
    }
}
