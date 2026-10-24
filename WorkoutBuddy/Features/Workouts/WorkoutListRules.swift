import Foundation

/// The second line of a Workouts list row: how many exercises the template has and when it was last done.
nonisolated struct WorkoutRowSubtitle: Equatable {
    /// The template can't be started (no exercises). The row shows a warning instead of the count.
    let needsExercises: Bool
    /// "5 exercises", "1 exercise" or "No exercises".
    let countText: String
    /// "Last done 12 Oct 2026" or "Not done yet".
    let performedText: String

    /// "5 exercises · Last done 12 Oct 2026".
    var text: String { "\(countText) · \(performedText)" }

    /// For VoiceOver: a template that can't start reads "Needs exercises" instead of "No exercises".
    var spokenText: String { "\(needsExercises ? "Needs exercises" : countText), \(performedText)" }
}

/// The Workouts list's decisions that don't need a view: sorting, the row text and the navigation path.
/// Pure, so it can be unit tested.
nonisolated enum WorkoutListRules {
    /// By name, the way Finder sorts ("Push 2" before "Push 10", case ignored). Names are unique among
    /// active templates; creation date and ID only make the order deterministic.
    static func sortedByName(_ workouts: [Workout]) -> [Workout] {
        workouts.sorted { a, b in
            switch a.name.localizedStandardCompare(b.name) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame:
                a.createdAt != b.createdAt ? a.createdAt < b.createdAt : a.id.uuidString < b.id.uuidString
            }
        }
    }

    /// - Parameters:
    ///   - exerciseCount: rows of the template that have an exercise.
    ///   - canStart: `WorkoutLibrary.canStart`. When it's false, the count is replaced by "No exercises".
    ///   - lastPerformed: `WorkoutLibrary.lastPerformed`.
    static func subtitle(
        exerciseCount: Int, canStart: Bool, lastPerformed: Date?,
        locale: Locale = .current, timeZone: TimeZone = .current
    ) -> WorkoutRowSubtitle {
        let performedText: String
        if let lastPerformed {
            let style = Date.FormatStyle(
                date: .abbreviated, time: .omitted, locale: locale, calendar: locale.calendar, timeZone: timeZone)
            performedText = "Last done \(lastPerformed.formatted(style))"
        } else {
            performedText = "Not done yet"
        }
        return WorkoutRowSubtitle(
            needsExercises: !canStart,
            countText: canStart ? SetSummary.count(exerciseCount, "exercise") : "No exercises",
            performedText: performedText)
    }

    /// The path after the template with `id` was deleted: everything from its first screen on is dropped,
    /// so the pop happens once. A path without `id` is returned unchanged.
    static func path(afterDeleting id: UUID, from path: [UUID]) -> [UUID] {
        guard let index = path.firstIndex(of: id) else { return path }
        return Array(path[..<index])
    }
}
