import Testing
@testable import WorkoutBuddy

struct ExercisePickerRulesTests {
    @Test func filterLabelIsFixed() {
        #expect(ExercisePickerRules.filterAccessibilityLabel == "Muscle Group Filter")
    }

    @Test func filterValueNamesAllGroupsWithoutFilter() {
        #expect(ExercisePickerRules.filterAccessibilityValue(for: nil) == "All Muscle Groups")
    }

    @Test func filterValueNamesTheGroup() {
        #expect(ExercisePickerRules.filterAccessibilityValue(for: .chest) == "Chest")
        #expect(ExercisePickerRules.filterAccessibilityValue(for: .fullBody) == "Full body")
    }

    @Test func filterSymbolIsFilledOnlyWhenFiltering() {
        #expect(ExercisePickerRules.filterSymbol(for: nil) == "line.3.horizontal.decrease.circle")
        #expect(ExercisePickerRules.filterSymbol(for: .legs) == "line.3.horizontal.decrease.circle.fill")
    }

    @Test func noEmptyStateWhenThereAreExercises() {
        #expect(ExercisePickerRules.emptyState(visibleCount: 3, inScopeCount: 5, searchText: "", group: nil) == .none)
        #expect(ExercisePickerRules.emptyState(visibleCount: 1, inScopeCount: 1, searchText: "bench", group: .chest) == .none)
    }

    @Test func searchWithoutMatchesShowsSearch() {
        #expect(ExercisePickerRules.emptyState(visibleCount: 0, inScopeCount: 5, searchText: "zzz", group: nil) == .search("zzz"))
        #expect(ExercisePickerRules.emptyState(visibleCount: 0, inScopeCount: 2, searchText: "zzz", group: .back) == .search("zzz"))
    }

    @Test func emptyFilterShowsNoExercisesForTheGroup() {
        #expect(ExercisePickerRules.emptyState(visibleCount: 0, inScopeCount: 0, searchText: "", group: .core) == .noExercises(.core))
    }

    @Test func emptyFilterWinsOverSearch() {
        // Nothing in the group at all, so "No Exercises" is more accurate than "No Results for ...".
        #expect(ExercisePickerRules.emptyState(visibleCount: 0, inScopeCount: 0, searchText: "zzz", group: .core) == .noExercises(.core))
    }

    @Test func noExercisesAtAllShowsGenericEmptyState() {
        #expect(ExercisePickerRules.emptyState(visibleCount: 0, inScopeCount: 0, searchText: "", group: nil) == .noExercises(nil))
    }

    @Test func emptyDescriptionNamesTheGroup() {
        #expect(ExercisePickerRules.noExercisesDescription(for: .chest) == "No exercises in Chest.")
        #expect(ExercisePickerRules.noExercisesDescription(for: .fullBody) == "No exercises in Full body.")
    }

    @Test func emptyDescriptionPointsToSettingsWithoutFilter() {
        #expect(ExercisePickerRules.noExercisesDescription(for: nil) == "Add exercises in Settings → Exercises.")
    }

    @Test func addedAnnouncementNamesTheExercise() {
        #expect(ExercisePickerRules.addedAnnouncement(for: "Bench Press") == "Bench Press added")
    }
}
