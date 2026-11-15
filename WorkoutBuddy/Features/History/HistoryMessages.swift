import Foundation

/// User-facing texts of the History tab. Pure, so it can be unit tested. Names are never stored in a
/// session, so callers look them up from the references and pass them in.
nonisolated enum HistoryMessages {
    static let tabTitle = "History"
    static let emptyTitle = "No workouts yet"
    static let emptyMessage = "Saved workouts appear here."
    static let todayButton = "Today"
    static let notFoundTitle = "Workout Not Found"

    static let endedEarlyText = "Ended early"
    static let skippedText = "Skipped"
    static let notPerformedText = "Not performed"

    static let deleteButton = "Delete"
    static let deleteTitle = "Delete Workout?"
    static let cancelButton = "Cancel"

    /// "The workout from Saturday, 14 November will be removed from your history. This can't be undone."
    static func deleteMessage(startedAt: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        "The workout from \(Formatters.dayTitle(startedAt, locale: locale, timeZone: timeZone)) "
            + "will be removed from your history. This can't be undone."
    }

    /// "Planned 10 × 60 kg".
    static func plannedText(_ planned: SetValues, locale: Locale = .current) -> String {
        "Planned \(SetSummary.line(planned, locale: locale))"
    }

    /// "planned 10 reps at 60 kilograms".
    static func spokenPlannedText(_ planned: SetValues, locale: Locale = .current) -> String {
        "planned \(SetSummary.spokenLine(planned, locale: locale))"
    }

    /// A workout name for a title or a row: the looked-up name, or the fallback when the reference is gone.
    static func workoutName(_ name: String?) -> String {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return SessionMessages.fallbackWorkoutName
        }
        return name
    }

    // MARK: Day list

    /// The second line of a day list row: "18:30 · 1 hr, 5 min".
    static func dayRowDetail(
        startedAt: Date, stats: SessionStats, locale: Locale = .current, timeZone: TimeZone = .current
    ) -> String {
        "\(Formatters.startTime(startedAt, locale: locale, timeZone: timeZone)) · "
            + SessionMessages.durationText(stats, locale: locale)
    }

    /// Spoken form of a day list row: "Push Day, 18:30, 1 hour, 5 minutes".
    static func spokenDayRow(
        name: String?, startedAt: Date, stats: SessionStats, locale: Locale = .current, timeZone: TimeZone = .current
    ) -> String {
        "\(workoutName(name)), \(Formatters.startTime(startedAt, locale: locale, timeZone: timeZone)), "
            + SessionMessages.spokenDurationText(stats, locale: locale)
    }
}
