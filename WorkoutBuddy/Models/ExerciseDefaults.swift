import Foundation

/// An exercise's own defaults for a new set. `nil` means "not set": the value then comes from the
/// last template that used the exercise, then from Settings.
nonisolated struct ExerciseDefaults: Equatable, Sendable {
    var reps: Int?
    var kg: Double?
    var restSeconds: Int?

    static let none = ExerciseDefaults(reps: nil, kg: nil, restSeconds: nil)

    /// Clamps reps and rest and snaps kg to the 0.5 kg grid. Unset values stay unset.
    func clamped() -> ExerciseDefaults {
        ExerciseDefaults(
            reps: reps.map(AppSettings.clampReps),
            kg: kg.map(AppSettings.snapKg),
            restSeconds: restSeconds.map(AppSettings.clampRest))
    }
}
