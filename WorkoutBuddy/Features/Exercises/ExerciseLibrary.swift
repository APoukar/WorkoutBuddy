import Foundation
import SwiftData

enum ExerciseNameError: Error, Equatable {
    case empty
    case duplicate
}

/// Exercise library operations. Every change is saved immediately.
@MainActor
struct ExerciseLibrary {
    let context: ModelContext

    /// Checks a name against the rules: not empty, and unique (case-insensitive) among active exercises.
    /// Pass `excluding` when renaming so the exercise doesn't clash with itself.
    /// A failed fetch counts as "no error" here; `add` and `rename` re-validate with a throwing fetch before saving.
    func validate(name: String, excluding: Exercise? = nil) -> ExerciseNameError? {
        (try? checkName(name, excluding: excluding)) ?? nil
    }

    private func checkName(_ name: String, excluding: Exercise?) throws -> ExerciseNameError? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        let active = try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { !$0.isArchived }))
        let clash = active.contains {
            $0.id != excluding?.id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        return clash ? .duplicate : nil
    }

    @discardableResult
    func add(name: String, muscleGroup: MuscleGroup, defaults: ExerciseDefaults = .none) throws -> Exercise {
        if let error = try checkName(name, excluding: nil) { throw error }
        let exercise = Exercise(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines), muscleGroup: muscleGroup, isCustom: true)
        exercise.defaults = defaults.clamped()
        context.insert(exercise)
        do { try context.save() } catch { context.rollback(); throw error }
        return exercise
    }

    /// Edits name, muscle group and defaults together: validates, sets every field and saves once,
    /// so an edit is never half saved. Defaults are stored clamped.
    func update(_ exercise: Exercise, name: String, muscleGroup: MuscleGroup, defaults: ExerciseDefaults) throws {
        if let error = try checkName(name, excluding: exercise) { throw error }
        exercise.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        exercise.muscleGroup = muscleGroup
        exercise.defaults = defaults.clamped()
        do { try context.save() } catch { context.rollback(); throw error }
    }

    /// Lookup by ID. Deliberately does not filter out archived exercises.
    func exercise(id: UUID) -> Exercise? {
        var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Active (not soft-deleted) templates containing the exercise, sorted by name.
    func workoutsUsing(_ exercise: Exercise) throws -> [Workout] {
        let workouts = try context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { !$0.isSoftDeleted }))
        return workouts
            .filter { $0.exercises.contains { $0.exercise?.id == exercise.id } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The confirmation text for deleting `exercise`, naming the templates it is removed from.
    func deletionWarning(for exercise: Exercise) throws -> ExerciseDeletionWarning {
        let workouts = try workoutsUsing(exercise)
        let emptied = workouts.filter { workout in
            workout.exercises.allSatisfy { $0.exercise?.id == exercise.id }
        }
        return .make(
            exerciseName: exercise.name, templateNames: workouts.map(\.name),
            emptiedTemplateNames: emptied.map(\.name))
    }

    /// "Delete": archives the exercise and removes it from every template (soft-deleted ones too),
    /// renumbering what's left. Sessions are never touched. Committed with a single save; rolled back on failure.
    func archive(_ exercise: Exercise) throws {
        let exerciseID = exercise.id
        let all = try context.fetch(FetchDescriptor<WorkoutExercise>())
        let rows = all.filter { $0.exercise?.id == exerciseID }
        let removedIDs = Set(rows.map(\.id))

        var seen = Set<UUID>()
        for workout in rows.compactMap(\.workout) where seen.insert(workout.id).inserted {
            let remaining = workout.orderedExercises.filter { !removedIDs.contains($0.id) }
            for (index, row) in remaining.enumerated() { row.order = index }
        }
        exercise.isArchived = true
        for row in rows { context.delete(row) }
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
