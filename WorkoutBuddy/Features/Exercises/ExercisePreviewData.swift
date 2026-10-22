import Foundation
import SwiftData

/// Preview helper: an in-memory, seeded container with a "Push Day" template that contains Bench Press.
@MainActor
enum ExercisePreviewData {
    static func container() -> ModelContainer {
        let container = try! ModelContainerFactory.make(inMemory: true)
        WorkoutBuddyApp.seed(container)
        let context = container.mainContext
        if let bench = benchPress(in: container) {
            let workout = Workout(name: "Push Day")
            context.insert(workout)
            let row = WorkoutExercise(order: 0, exercise: bench)
            row.workout = workout
            context.insert(row)
            let set = PlannedSet(order: 0, reps: 10, kg: 60, restSeconds: 90)
            set.workoutExercise = row
            context.insert(set)
            try? context.save()
        }
        return container
    }

    static func benchPress(in container: ModelContainer) -> Exercise? {
        try? container.mainContext.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == "Bench Press" })).first
    }
}
