import Foundation
import SwiftData

/// Preview helper: builds on `ExercisePreviewData` ("Push Day" with Bench Press) and adds
/// Overhead Press to "Push Day", a "Legs" template with one finished session, a "Core" template with
/// a 0 kg set, and an "Empty" template with no exercises.
/// Compiled in every configuration (no `#if DEBUG`), because a Debug-only helper broke the Release build.
@MainActor
enum WorkoutPreviewData {
    static func container() -> ModelContainer {
        let container = ExercisePreviewData.container()
        let context = container.mainContext
        let library = WorkoutLibrary(context: context)

        // Push Day: add Overhead Press after Bench Press.
        if let pushDay = workout(named: "Push Day", in: container), let press = exercise(named: "Overhead Press", in: container) {
            var draft = library.draft(for: pushDay)
            draft.addExercise(exerciseID: press.id, firstSet: SetValues(reps: 8, kg: 40, restSeconds: 120))
            _ = try? library.save(draft, to: pushDay)
        }

        // Legs: two exercises and one finished session, for the last-performed date.
        var legs = WorkoutDraft(name: "Legs")
        if let squat = exercise(named: "Back Squat", in: container) {
            legs.addExercise(exerciseID: squat.id, firstSet: SetValues(reps: 5, kg: 100, restSeconds: 180))
            if let id = legs.exercises.last?.id {
                legs.addSet(toExercise: id)
                legs.addSet(toExercise: id)
            }
        }
        if let legPress = exercise(named: "Leg Press", in: container) {
            legs.addExercise(exerciseID: legPress.id, firstSet: SetValues(reps: 12, kg: 140, restSeconds: 90))
        }
        if let legsWorkout = try? library.save(legs, to: nil) {
            let started = Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now
            let session = WorkoutSession(
                workout: legsWorkout, startedAt: started, endedAt: started.addingTimeInterval(55 * 60), status: .completed)
            context.insert(session)
            for row in legsWorkout.orderedExercises {
                let sessionExercise = SessionExercise(order: row.order, exercise: row.exercise)
                context.insert(sessionExercise)
                sessionExercise.session = session
                for set in row.orderedSets {
                    let sessionSet = SessionSet(
                        order: set.order, plannedReps: set.reps, plannedKg: set.kg, plannedRestSeconds: set.restSeconds,
                        actualReps: set.reps, actualKg: set.kg, status: .done, completedAt: started)
                    context.insert(sessionSet)
                    sessionSet.sessionExercise = sessionExercise
                }
            }
            try? context.save()
        }

        // Core: a 0 kg set (shown as "Bodyweight") next to a weighted one.
        var core = WorkoutDraft(name: "Core")
        if let crunch = exercise(named: "Crunch", in: container) {
            core.addExercise(exerciseID: crunch.id, firstSet: SetValues(reps: 15, kg: 0, restSeconds: 60))
        }
        if let cableCrunch = exercise(named: "Cable Crunch", in: container) {
            core.addExercise(exerciseID: cableCrunch.id, firstSet: SetValues(reps: 12, kg: 30, restSeconds: 60))
        }
        _ = try? library.save(core, to: nil)

        // Empty: a template that can't start. A draft can't be saved without an exercise, so it is inserted directly.
        context.insert(Workout(name: "Empty"))
        try? context.save()
        return container
    }

    static func workout(named name: String, in container: ModelContainer) -> Workout? {
        try? container.mainContext.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.name == name })).first
    }

    static func exercise(named name: String, in container: ModelContainer) -> Exercise? {
        try? container.mainContext.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == name })).first
    }
}
