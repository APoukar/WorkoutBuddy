import Foundation

/// The F2 first-set rule: when an exercise is added to a template, each value of its first set comes from
/// the exercise's own default if set, else from the last-used set, else from Settings.
nonisolated enum FirstSetDefaults {
    /// Resolves reps, kg and rest independently, so one source can supply some values and another the rest.
    static func resolve(exercise: ExerciseDefaults, lastUsed: SetValues?, settings: AppSettings.Values) -> SetValues {
        SetValues(
            reps: exercise.reps ?? lastUsed?.reps ?? settings.reps,
            kg: exercise.kg ?? lastUsed?.kg ?? settings.kg,
            restSeconds: exercise.restSeconds ?? lastUsed?.restSeconds ?? settings.restSeconds)
    }
}
