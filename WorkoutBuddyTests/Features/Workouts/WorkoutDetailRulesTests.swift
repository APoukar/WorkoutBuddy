import Foundation
import Testing
@testable import WorkoutBuddy

struct WorkoutDetailRulesTests {
    private let enUS = Locale(identifier: "en_US")
    private let enCZ = Locale(identifier: "en_CZ")

    @Test func setLabelCombinesTitleRepsWeightAndRest() {
        let label = WorkoutDetailRules.setAccessibilityLabel(
            forSetAt: 0, values: SetValues(reps: 10, kg: 60, restSeconds: 90), locale: enUS)
        #expect(label == "Set 1, 10 reps at 60 kilograms, rest 1 minute, 30 seconds")
    }

    @Test func setLabelReadsBodyweight() {
        let label = WorkoutDetailRules.setAccessibilityLabel(
            forSetAt: 1, values: SetValues(reps: 1, kg: 0, restSeconds: 60), locale: enUS)
        #expect(label == "Set 2, 1 rep, bodyweight, rest 1 minute")
    }

    @Test func setLabelUsesTheRegionForNumbers() {
        let label = WorkoutDetailRules.setAccessibilityLabel(
            forSetAt: 2, values: SetValues(reps: 8, kg: 22.5, restSeconds: 45), locale: enCZ)
        #expect(label == "Set 3, 8 reps at 22,5 kilograms, rest 45 seconds")
    }

    @Test func hintTellsWhatToDo() {
        #expect(WorkoutDetailRules.cannotStartHint == "Add an exercise to start this workout.")
    }

    @Test func startNeedsAStartableActiveTemplate() {
        #expect(WorkoutDetailRules.isStartEnabled(canStart: true, isSoftDeleted: false))
        #expect(!WorkoutDetailRules.isStartEnabled(canStart: false, isSoftDeleted: false))
        #expect(!WorkoutDetailRules.isStartEnabled(canStart: true, isSoftDeleted: true))
        #expect(!WorkoutDetailRules.isStartEnabled(canStart: false, isSoftDeleted: true))
    }
}
