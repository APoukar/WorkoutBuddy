import Foundation
import Testing
@testable import WorkoutBuddy

struct SetSummaryTests {
    private let us = Locale(identifier: "en_US")
    private let enCZ = Locale(identifier: "en_CZ")

    private func set(_ reps: Int, _ kg: Double, rest: Int = 90) -> SetValues {
        SetValues(reps: reps, kg: kg, restSeconds: rest)
    }

    private func summary(_ sets: [SetValues], locale: Locale? = nil) -> String {
        SetSummary.summary(of: sets, locale: locale ?? us)
    }

    private func spoken(_ sets: [SetValues], locale: Locale? = nil) -> String {
        SetSummary.spokenSummary(of: sets, locale: locale ?? us)
    }

    // MARK: One set

    @Test func lineForOneSet() {
        #expect(SetSummary.line(set(10, 60), locale: us) == "10 × 60\u{00A0}kg")
        #expect(SetSummary.line(set(10, 22.5), locale: us) == "10 × 22.5\u{00A0}kg")
        #expect(SetSummary.line(set(10, 22.5), locale: enCZ) == "10 × 22,5\u{00A0}kg")
        #expect(SetSummary.line(set(10, 0), locale: us) == "10 × Bodyweight")
        #expect(SetSummary.line(set(1, 0.5), locale: us) == "1 × 0.5\u{00A0}kg")
    }

    @Test func spokenLineForOneSet() {
        #expect(SetSummary.spokenLine(set(10, 60), locale: us) == "10 reps at 60 kilograms")
        #expect(SetSummary.spokenLine(set(10, 22.5), locale: enCZ) == "10 reps at 22,5 kilograms")
        #expect(SetSummary.spokenLine(set(10, 0), locale: us) == "10 reps, bodyweight")
        #expect(SetSummary.spokenLine(set(1, 1), locale: us) == "1 rep at 1 kilogram")
        #expect(SetSummary.spokenLine(set(1, 0), locale: us) == "1 rep, bodyweight")
    }

    // MARK: Equal sets

    @Test func equalSets() {
        #expect(summary([set(10, 60), set(10, 60), set(10, 60)]) == "3 × 10 × 60\u{00A0}kg")
        #expect(summary([set(10, 22.5), set(10, 22.5)], locale: enCZ) == "2 × 10 × 22,5\u{00A0}kg")
    }

    @Test func equalSetsAtZeroKgReadBodyweight() {
        #expect(summary([set(10, 0), set(10, 0), set(10, 0)]) == "3 × 10 · Bodyweight")
    }

    @Test func oneSet() {
        #expect(summary([set(10, 60)]) == "1 × 10 × 60\u{00A0}kg")
        #expect(summary([set(10, 0)]) == "1 × 10 · Bodyweight")
    }

    @Test func restIsNotComparedBecauseItIsNotShown() {
        #expect(summary([set(10, 60, rest: 60), set(10, 60, rest: 180)]) == "2 × 10 × 60\u{00A0}kg")
    }

    @Test func spokenEqualSets() {
        #expect(spoken([set(10, 60), set(10, 60), set(10, 60)]) == "3 sets of 10 reps at 60 kilograms")
        #expect(spoken([set(10, 22.5), set(10, 22.5)], locale: enCZ) == "2 sets of 10 reps at 22,5 kilograms")
        #expect(spoken([set(10, 0), set(10, 0)]) == "2 sets of 10 reps, bodyweight")
    }

    @Test func singularForms() {
        #expect(spoken([set(10, 60)]) == "1 set of 10 reps at 60 kilograms")
        #expect(spoken([set(1, 60), set(1, 60), set(1, 60)]) == "3 sets of 1 rep at 60 kilograms")
        #expect(spoken([set(1, 1)]) == "1 set of 1 rep at 1 kilogram")
        #expect(spoken([set(1, 0)]) == "1 set of 1 rep, bodyweight")
        #expect(summary([set(1, 60), set(1, 80)]) == "2 sets · 1 rep · 60–80\u{00A0}kg")
        #expect(spoken([set(1, 60), set(1, 80)]) == "2 sets, 1 rep, 60 to 80 kilograms")
        #expect(SetSummary.count(1, "set") == "1 set")
        #expect(SetSummary.count(0, "set") == "0 sets")
        #expect(SetSummary.count(2, "rep") == "2 reps")
    }

    // MARK: Different sets

    @Test func rangesInRepsAndKg() {
        #expect(summary([set(8, 60), set(10, 70), set(12, 80)]) == "3 sets · 8–12 reps · 60–80\u{00A0}kg")
        #expect(summary([set(12, 60), set(8, 80)]) == "2 sets · 8–12 reps · 60–80\u{00A0}kg")
        #expect(summary([set(8, 22.5), set(10, 25)], locale: enCZ) == "2 sets · 8–10 reps · 22,5–25\u{00A0}kg")
    }

    @Test func leavesOutARangeWhoseValuesAreAllEqual() {
        #expect(summary([set(10, 60), set(10, 70), set(10, 80)]) == "3 sets · 10 reps · 60–80\u{00A0}kg")
        #expect(summary([set(8, 60), set(10, 60), set(12, 60)]) == "3 sets · 8–12 reps · 60\u{00A0}kg")
    }

    @Test func aRangeThatIncludesZeroShowsNumbers() {
        #expect(summary([set(10, 0), set(10, 20)]) == "2 sets · 10 reps · 0–20\u{00A0}kg")
        #expect(summary([set(8, 0), set(12, 20)]) == "2 sets · 8–12 reps · 0–20\u{00A0}kg")
        #expect(spoken([set(10, 0), set(10, 20)]) == "2 sets, 10 reps, 0 to 20 kilograms")
    }

    @Test func bodyweightOnlyWhenEverySetIsZero() {
        #expect(summary([set(8, 0), set(10, 0), set(12, 0)]) == "3 sets · 8–12 reps · Bodyweight")
        #expect(spoken([set(8, 0), set(12, 0)]) == "2 sets, 8 to 12 reps, bodyweight")
    }

    @Test func spokenDifferentSets() {
        #expect(spoken([set(8, 60), set(10, 70), set(12, 80)]) == "3 sets, 8 to 12 reps, 60 to 80 kilograms")
        #expect(spoken([set(10, 60), set(10, 70)]) == "2 sets, 10 reps, 60 to 70 kilograms")
        #expect(spoken([set(8, 60), set(12, 60)]) == "2 sets, 8 to 12 reps, 60 kilograms")
        #expect(spoken([set(8, 60), set(12, 60)], locale: enCZ) == "2 sets, 8 to 12 reps, 60 kilograms")
        #expect(spoken([set(8, 22.5), set(12, 25)], locale: enCZ) == "2 sets, 8 to 12 reps, 22,5 to 25 kilograms")
    }

    @Test func noSets() {
        #expect(summary([]) == "No sets")
        #expect(spoken([]) == "No sets")
    }
}
