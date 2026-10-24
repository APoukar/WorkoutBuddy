import Foundation
import SwiftData

/// Schema V1. Editable in place during development; frozen once the app is on a device with real data.
/// Enums are stored as raw strings (`...Raw`) so `#Predicate` stays reliable on iOS 18.
nonisolated enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Exercise.self, Workout.self, WorkoutExercise.self, PlannedSet.self,
            WorkoutSession.self, SessionExercise.self, SessionSet.self,
        ]
    }

    @Model
    nonisolated final class Exercise {
        var id: UUID = UUID()
        var name: String = ""
        var muscleGroupRaw: String = MuscleGroup.fullBody.rawValue
        var isCustom: Bool = false
        var isArchived: Bool = false
        /// Optional defaults for a new set of this exercise. `nil` means "not set".
        var defaultReps: Int?
        var defaultKg: Double?
        var defaultRestSeconds: Int?

        var muscleGroup: MuscleGroup {
            get { MuscleGroup(rawValue: muscleGroupRaw) ?? .fullBody }
            set { muscleGroupRaw = newValue.rawValue }
        }

        init(
            id: UUID = UUID(), name: String, muscleGroup: MuscleGroup, isCustom: Bool = false, isArchived: Bool = false,
            defaultReps: Int? = nil, defaultKg: Double? = nil, defaultRestSeconds: Int? = nil
        ) {
            self.id = id
            self.name = name
            self.muscleGroupRaw = muscleGroup.rawValue
            self.isCustom = isCustom
            self.isArchived = isArchived
            self.defaultReps = defaultReps
            self.defaultKg = defaultKg
            self.defaultRestSeconds = defaultRestSeconds
        }
    }

    /// A workout template. Named `isSoftDeleted` because `PersistentModel` already has `isDeleted`.
    @Model
    nonisolated final class Workout {
        var id: UUID = UUID()
        var name: String = ""
        var createdAt: Date = Date.now
        /// When the template was last saved through the editor. Decides which template counts as "last used".
        var updatedAt: Date = Date.now
        var isSoftDeleted: Bool = false

        @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout)
        var exercises: [WorkoutExercise] = []

        @Relationship(deleteRule: .nullify, inverse: \WorkoutSession.workout)
        var sessions: [WorkoutSession] = []

        var orderedExercises: [WorkoutExercise] {
            exercises.sorted { $0.order < $1.order }
        }

        init(
            id: UUID = UUID(), name: String, createdAt: Date = .now, updatedAt: Date? = nil, isSoftDeleted: Bool = false
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.updatedAt = updatedAt ?? createdAt
            self.isSoftDeleted = isSoftDeleted
        }
    }

    @Model
    nonisolated final class WorkoutExercise {
        var id: UUID = UUID()
        var order: Int = 0
        var workout: Workout?
        var exercise: Exercise?

        @Relationship(deleteRule: .cascade, inverse: \PlannedSet.workoutExercise)
        var sets: [PlannedSet] = []

        var orderedSets: [PlannedSet] {
            sets.sorted { $0.order < $1.order }
        }

        init(id: UUID = UUID(), order: Int, exercise: Exercise?) {
            self.id = id
            self.order = order
            self.exercise = exercise
        }
    }

    @Model
    nonisolated final class PlannedSet {
        var id: UUID = UUID()
        var order: Int = 0
        var workoutExercise: WorkoutExercise?
        var reps: Int = 0
        var kg: Double = 0
        var restSeconds: Int = 0

        init(id: UUID = UUID(), order: Int, reps: Int, kg: Double, restSeconds: Int) {
            self.id = id
            self.order = order
            self.reps = reps
            self.kg = kg
            self.restSeconds = restSeconds
        }
    }

    @Model
    nonisolated final class WorkoutSession {
        var id: UUID = UUID()
        var workout: Workout?
        var startedAt: Date = Date.now
        var endedAt: Date?
        var pausedDuration: TimeInterval = 0
        var statusRaw: String = SessionStatus.inProgress.rawValue

        @Relationship(deleteRule: .cascade, inverse: \SessionExercise.session)
        var exercises: [SessionExercise] = []

        var status: SessionStatus {
            get { SessionStatus(rawValue: statusRaw) ?? .inProgress }
            set { statusRaw = newValue.rawValue }
        }

        var orderedExercises: [SessionExercise] {
            exercises.sorted { $0.order < $1.order }
        }

        init(
            id: UUID = UUID(), workout: Workout?, startedAt: Date = .now, endedAt: Date? = nil,
            pausedDuration: TimeInterval = 0, status: SessionStatus = .inProgress
        ) {
            self.id = id
            self.workout = workout
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.pausedDuration = pausedDuration
            self.statusRaw = status.rawValue
        }
    }

    @Model
    nonisolated final class SessionExercise {
        var id: UUID = UUID()
        var order: Int = 0
        var session: WorkoutSession?
        var exercise: Exercise?

        @Relationship(deleteRule: .cascade, inverse: \SessionSet.sessionExercise)
        var sets: [SessionSet] = []

        var orderedSets: [SessionSet] {
            sets.sorted { $0.order < $1.order }
        }

        init(id: UUID = UUID(), order: Int, exercise: Exercise?) {
            self.id = id
            self.order = order
            self.exercise = exercise
        }
    }

    @Model
    nonisolated final class SessionSet {
        var id: UUID = UUID()
        var order: Int = 0
        var sessionExercise: SessionExercise?
        var plannedReps: Int = 0
        var plannedKg: Double = 0
        var plannedRestSeconds: Int = 0
        var actualReps: Int?
        var actualKg: Double?
        var statusRaw: String = SetStatus.pending.rawValue
        var completedAt: Date?

        var status: SetStatus {
            get { SetStatus(rawValue: statusRaw) ?? .pending }
            set { statusRaw = newValue.rawValue }
        }

        init(
            id: UUID = UUID(), order: Int, plannedReps: Int, plannedKg: Double, plannedRestSeconds: Int,
            actualReps: Int? = nil, actualKg: Double? = nil, status: SetStatus = .pending, completedAt: Date? = nil
        ) {
            self.id = id
            self.order = order
            self.plannedReps = plannedReps
            self.plannedKg = plannedKg
            self.plannedRestSeconds = plannedRestSeconds
            self.actualReps = actualReps
            self.actualKg = actualKg
            self.statusRaw = status.rawValue
            self.completedAt = completedAt
        }
    }
}

typealias Exercise = SchemaV1.Exercise
typealias Workout = SchemaV1.Workout
typealias WorkoutExercise = SchemaV1.WorkoutExercise
typealias PlannedSet = SchemaV1.PlannedSet
typealias WorkoutSession = SchemaV1.WorkoutSession
typealias SessionExercise = SchemaV1.SessionExercise
typealias SessionSet = SchemaV1.SessionSet
