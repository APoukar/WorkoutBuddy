import Foundation
import SwiftData

/// Why a draft could not be saved, besides a name error (`NameError`).
nonisolated enum WorkoutSaveError: Error, Equatable {
    /// The draft has issues (`WorkoutDraft.issues`), or repeats an exercise, a row ID, or a set ID within a row.
    case invalid
    /// An exercise in the draft doesn't exist any more, or is archived.
    case missingExercise
}

/// Workout template operations. Every change is saved immediately; a failed save is rolled back.
@MainActor
struct WorkoutLibrary {
    let context: ModelContext

    private var exercises: ExerciseLibrary { ExerciseLibrary(context: context) }

    // MARK: Names

    /// Checks a name against the rules: not empty, and unique (case-insensitive) among active templates.
    /// Pass `excluding` when renaming so the template doesn't clash with itself.
    /// A failed fetch counts as "no error" here; `save` re-validates with a throwing fetch.
    func validate(name: String, excluding: Workout? = nil) -> NameError? {
        (try? checkName(name, excluding: excluding)) ?? nil
    }

    private func checkName(_ name: String, excluding: Workout?) throws -> NameError? {
        // An empty name needs no fetch, so it's reported even if the fetch would fail.
        if NameRules.check(name, against: []) == .empty { return .empty }
        let active = try context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { !$0.isSoftDeleted }))
        return NameRules.check(name, against: active.map { (id: $0.id, name: $0.name) }, excluding: excluding?.id)
    }

    // MARK: Drafts

    /// An empty draft for a new template, or a copy of the template with its row IDs, in order.
    /// Rows whose exercise is missing (`nil`) are skipped.
    func draft(for workout: Workout?) -> WorkoutDraft {
        guard let workout else { return WorkoutDraft() }
        let rows = workout.orderedExercises.compactMap { row -> DraftExercise? in
            guard let exercise = row.exercise else { return nil }
            let sets = row.orderedSets.map {
                DraftSet(id: $0.id, values: SetValues(reps: $0.reps, kg: $0.kg, restSeconds: $0.restSeconds))
            }
            return DraftExercise(id: row.id, exerciseID: exercise.id, sets: sets)
        }
        return WorkoutDraft(name: workout.name, exercises: rows)
    }

    /// Writes the draft to the store in one save: creates a template when `workout` is `nil`,
    /// otherwise updates it. Rows and sets are matched by ID so existing IDs stay stable.
    /// Everything that can fail is checked before the first change; a later failure rolls back.
    @discardableResult
    func save(_ draft: WorkoutDraft, to workout: Workout?, now: Date = .now) throws -> Workout {
        // 1. Checks that need no changes to the context.
        if let error = try checkName(draft.name, excluding: workout) { throw error }
        guard draft.issues.isEmpty, !Self.hasRepeats(draft) else { throw WorkoutSaveError.invalid }
        var resolved: [UUID: Exercise] = [:]
        for row in draft.exercises {
            // Unlike plain ID lookups, a template must never get an archived exercise back.
            guard let exercise = exercises.exercise(id: row.exerciseID), !exercise.isArchived else {
                throw WorkoutSaveError.missingExercise
            }
            resolved[row.exerciseID] = exercise
        }

        // 2. Changes. From here on, any error rolls everything back.
        do {
            let target: Workout
            if let workout {
                target = workout
            } else {
                target = Workout(name: "", createdAt: now)
                context.insert(target)
            }
            target.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            target.updatedAt = now

            let existingRows = Dictionary(target.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var removedSets: [PlannedSet] = []
            for (index, draftRow) in draft.exercises.enumerated() {
                let row: WorkoutExercise
                if let existing = existingRows[draftRow.id] {
                    row = existing
                } else {
                    row = WorkoutExercise(id: draftRow.id, order: index, exercise: nil)
                    context.insert(row)
                    row.workout = target
                }
                row.order = index
                row.exercise = resolved[draftRow.exerciseID]

                let existingSets = Dictionary(row.sets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                for (setIndex, draftSet) in draftRow.sets.enumerated() {
                    let set: PlannedSet
                    if let existing = existingSets[draftSet.id] {
                        set = existing
                    } else {
                        set = PlannedSet(id: draftSet.id, order: setIndex, reps: 0, kg: 0, restSeconds: 0)
                        context.insert(set)
                        set.workoutExercise = row
                    }
                    set.order = setIndex
                    set.reps = AppSettings.clampReps(draftSet.values.reps)
                    set.kg = AppSettings.snapKg(draftSet.values.kg)
                    set.restSeconds = AppSettings.clampRest(draftSet.values.restSeconds)
                }
                let keptSetIDs = Set(draftRow.sets.map(\.id))
                removedSets += row.sets.filter { !keptSetIDs.contains($0.id) }
            }

            // Every order is set; only now delete what the draft no longer has.
            let keptRowIDs = Set(draft.exercises.map(\.id))
            let removedRows = target.exercises.filter { !keptRowIDs.contains($0.id) }
            for set in removedSets { context.delete(set) }
            for row in removedRows { context.delete(row) }

            try context.save()
            return target
        } catch {
            context.rollback()
            throw error
        }
    }

    /// A repeated exercise, row ID, or set ID within a row. The editor can't produce these, but a draft
    /// built in code could: they would break "each exercise once" or leave stale rows behind.
    private static func hasRepeats(_ draft: WorkoutDraft) -> Bool {
        let rows = draft.exercises
        if Set(rows.map(\.exerciseID)).count != rows.count { return true }
        if Set(rows.map(\.id)).count != rows.count { return true }
        return rows.contains { Set($0.sets.map(\.id)).count != $0.sets.count }
    }

    // MARK: Lookup and delete

    /// Lookup by ID. Deliberately does not filter out soft-deleted templates.
    func workout(id: UUID) -> Workout? {
        var descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Soft delete: hides the template from lists but keeps its rows, so sessions still reference it.
    func softDelete(_ workout: Workout) throws {
        workout.isSoftDeleted = true
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
