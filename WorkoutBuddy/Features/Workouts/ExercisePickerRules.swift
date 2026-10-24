import Foundation

/// The exercise picker's decisions that don't need a view: the filter's texts and which empty state to show.
/// Pure, so it can be unit tested.
nonisolated enum ExercisePickerRules {
    static let allGroupsTitle = "All Muscle Groups"

    /// The filter menu's accessibility label. The icon alone says nothing; the current filter is the value.
    static let filterAccessibilityLabel = "Muscle Group Filter"

    /// The filter menu's accessibility value: the current filter.
    static func filterAccessibilityValue(for group: MuscleGroup?) -> String {
        group?.displayName ?? allGroupsTitle
    }

    /// The filter menu's icon: filled while a filter is active.
    static func filterSymbol(for group: MuscleGroup?) -> String {
        group == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
    }

    enum EmptyState: Equatable {
        /// There are exercises to show.
        case none
        /// Nothing matches the search text.
        case search(String)
        /// There are no exercises at all (`nil`) or none in the filtered muscle group.
        case noExercises(MuscleGroup?)
    }

    /// The description under "No Exercises": the filtered muscle group is empty, or there are no exercises at all.
    static func noExercisesDescription(for group: MuscleGroup?) -> String {
        if let group { return "No exercises in \(group.displayName)." }
        return "Add exercises in Settings → Exercises."
    }

    /// The announcement after an exercise was picked, since the row only changes visually.
    static func addedAnnouncement(for exerciseName: String) -> String {
        "\(exerciseName) added"
    }

    /// - Parameters:
    ///   - visibleCount: exercises left after the filter and the search.
    ///   - inScopeCount: active exercises in the filtered muscle group (all of them without a filter), before searching.
    static func emptyState(visibleCount: Int, inScopeCount: Int, searchText: String, group: MuscleGroup?) -> EmptyState {
        guard visibleCount == 0 else { return .none }
        if inScopeCount == 0 { return .noExercises(group) }
        return .search(searchText)
    }
}
