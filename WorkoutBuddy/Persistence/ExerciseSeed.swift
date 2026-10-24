import Foundation
import SwiftData

/// The built-in exercise list, inserted once on the first launch.
enum ExerciseSeed {
    struct Entry: Equatable {
        let name: String
        let muscleGroup: MuscleGroup
    }

    static let entries: [Entry] = {
        let byGroup: [(MuscleGroup, [String])] = [
            (.chest, ["Bench Press", "Incline Bench Press", "Dumbbell Bench Press", "Incline Dumbbell Press", "Dumbbell Fly", "Push-Up"]),
            (.back, ["Deadlift", "Pull-Up", "Lat Pulldown", "Barbell Row", "Dumbbell Row", "Seated Cable Row"]),
            (.shoulders, ["Overhead Press", "Dumbbell Shoulder Press", "Lateral Raise", "Front Raise", "Rear Delt Fly", "Face Pull"]),
            (.biceps, ["Barbell Curl", "Dumbbell Curl", "Hammer Curl", "Preacher Curl"]),
            (.triceps, ["Triceps Pushdown", "Skull Crusher", "Overhead Triceps Extension", "Close-Grip Bench Press"]),
            (.legs, ["Back Squat", "Leg Press", "Romanian Deadlift", "Leg Extension", "Leg Curl", "Walking Lunge", "Standing Calf Raise"]),
            (.glutes, ["Hip Thrust", "Glute Bridge", "Bulgarian Split Squat"]),
            (.core, ["Crunch", "Hanging Leg Raise", "Cable Crunch", "Ab Wheel Rollout"]),
            (.fullBody, ["Power Clean", "Kettlebell Swing", "Thruster"]),
        ]
        return byGroup.flatMap { group, names in names.map { Entry(name: $0, muscleGroup: group) } }
    }()

    /// Inserts the seed list only when the store has no Exercise records at all (archived ones count), then saves.
    /// Returns whether anything was inserted.
    @discardableResult
    static func seedIfNeeded(in context: ModelContext) throws -> Bool {
        var descriptor = FetchDescriptor<Exercise>()
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else { return false }

        for entry in entries {
            context.insert(Exercise(name: entry.name, muscleGroup: entry.muscleGroup, isCustom: false))
        }
        try context.save()
        return true
    }
}
