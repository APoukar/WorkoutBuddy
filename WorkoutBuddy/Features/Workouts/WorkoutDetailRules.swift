import Foundation

/// The template detail screen's texts that need no view. Pure, so it can be unit tested.
nonisolated enum WorkoutDetailRules {
    /// Shown under the disabled Start Workout button.
    static let cannotStartHint = "Add an exercise to start this workout."

    /// Whether Start Workout is enabled: the template can start and isn't soft-deleted (the detail can
    /// still be open after the template was deleted).
    static func isStartEnabled(canStart: Bool, isSoftDeleted: Bool) -> Bool {
        canStart && !isSoftDeleted
    }

    /// One combined VoiceOver label for a set row: "Set 1, 10 reps at 60 kilograms, rest 1 minute, 30 seconds".
    static func setAccessibilityLabel(forSetAt index: Int, values: SetValues, locale: Locale = .current) -> String {
        let title = ExerciseSetsRules.sectionTitle(forSetAt: index)
        let rest = Formatters.spokenDuration(seconds: values.restSeconds, locale: locale)
        return "\(title), \(SetSummary.spokenLine(values, locale: locale)), rest \(rest)"
    }
}
