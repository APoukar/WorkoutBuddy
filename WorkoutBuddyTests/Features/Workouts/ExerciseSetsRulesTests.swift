import Testing
@testable import WorkoutBuddy

struct ExerciseSetsRulesTests {
    @Test func sectionTitlesAreOneBased() {
        #expect(ExerciseSetsRules.sectionTitle(forSetAt: 0) == "Set 1")
        #expect(ExerciseSetsRules.sectionTitle(forSetAt: 1) == "Set 2")
        #expect(ExerciseSetsRules.sectionTitle(forSetAt: 11) == "Set 12")
    }

    @Test func deleteLabelsDifferPerSet() {
        #expect(ExerciseSetsRules.deleteAccessibilityLabel(forSetAt: 0) == "Delete Set 1")
        #expect(ExerciseSetsRules.deleteAccessibilityLabel(forSetAt: 2) == "Delete Set 3")
    }

    @Test func deleteSetIsHiddenForTheOnlySet() {
        #expect(!ExerciseSetsRules.showsDeleteSet(setCount: 1))
        #expect(!ExerciseSetsRules.showsDeleteSet(setCount: 0))
    }

    @Test func deleteSetShowsWithSeveralSets() {
        #expect(ExerciseSetsRules.showsDeleteSet(setCount: 2))
        #expect(ExerciseSetsRules.showsDeleteSet(setCount: 5))
    }
}
