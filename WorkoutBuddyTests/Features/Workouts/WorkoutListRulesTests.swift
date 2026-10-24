import Foundation
import Testing
@testable import WorkoutBuddy

struct WorkoutListRulesTests {
    private let enUS = Locale(identifier: "en_US")
    private let enGB = Locale(identifier: "en_GB")
    private let utc = TimeZone(identifier: "UTC") ?? .gmt

    /// 12 Oct 2026, 12:00 UTC.
    private let oct12 = Date(timeIntervalSince1970: 1_791_806_400)

    // MARK: Sorting

    @Test func sortsByNameIgnoringCase() {
        let names = ["push", "Pull", "Legs", "arms"]
        let sorted = WorkoutListRules.sortedByName(names.map { Workout(name: $0) })
        #expect(sorted.map(\.name) == ["arms", "Legs", "Pull", "push"])
    }

    @Test func sortsNumbersNaturally() {
        let names = ["Day 10", "Day 2", "Day 1"]
        let sorted = WorkoutListRules.sortedByName(names.map { Workout(name: $0) })
        #expect(sorted.map(\.name) == ["Day 1", "Day 2", "Day 10"])
    }

    @Test func equalNamesKeepADeterministicOrder() {
        let early = Workout(name: "Same", createdAt: Date(timeIntervalSince1970: 100))
        let late = Workout(name: "Same", createdAt: Date(timeIntervalSince1970: 200))
        #expect(WorkoutListRules.sortedByName([late, early]).map(\.id) == [early.id, late.id])
        #expect(WorkoutListRules.sortedByName([early, late]).map(\.id) == [early.id, late.id])
    }

    @Test func sortingNothingGivesNothing() {
        #expect(WorkoutListRules.sortedByName([]).isEmpty)
    }

    // MARK: Row subtitle

    @Test func subtitleWithCountAndDate() {
        let subtitle = WorkoutListRules.subtitle(
            exerciseCount: 5, canStart: true, lastPerformed: oct12, locale: enGB, timeZone: utc)
        #expect(subtitle.text == "5 exercises · Last done 12 Oct 2026")
        #expect(subtitle.spokenText == "5 exercises, Last done 12 Oct 2026")
        #expect(!subtitle.needsExercises)
    }

    @Test func subtitleDateFollowsTheLocale() {
        let subtitle = WorkoutListRules.subtitle(
            exerciseCount: 2, canStart: true, lastPerformed: oct12, locale: enUS, timeZone: utc)
        #expect(subtitle.text == "2 exercises · Last done Oct 12, 2026")
    }

    @Test func subtitleDateFollowsTheTimeZone() {
        // 23:30 UTC on 12 Oct is already 13 Oct in Prague (UTC+2 in October).
        let lateEvening = oct12.addingTimeInterval(11.5 * 3600)
        let prague = TimeZone(identifier: "Europe/Prague") ?? .gmt
        #expect(WorkoutListRules.subtitle(
            exerciseCount: 1, canStart: true, lastPerformed: lateEvening, locale: enGB, timeZone: utc)
            .performedText == "Last done 12 Oct 2026")
        #expect(WorkoutListRules.subtitle(
            exerciseCount: 1, canStart: true, lastPerformed: lateEvening, locale: enGB, timeZone: prague)
            .performedText == "Last done 13 Oct 2026")
    }

    @Test func subtitleNotDoneYet() {
        let subtitle = WorkoutListRules.subtitle(
            exerciseCount: 3, canStart: true, lastPerformed: nil, locale: enGB, timeZone: utc)
        #expect(subtitle.text == "3 exercises · Not done yet")
        #expect(subtitle.spokenText == "3 exercises, Not done yet")
    }

    @Test func subtitleSingularExercise() {
        let subtitle = WorkoutListRules.subtitle(exerciseCount: 1, canStart: true, lastPerformed: nil)
        #expect(subtitle.countText == "1 exercise")
    }

    @Test func subtitleOfATemplateThatCannotStart() {
        let subtitle = WorkoutListRules.subtitle(
            exerciseCount: 0, canStart: false, lastPerformed: nil, locale: enGB, timeZone: utc)
        #expect(subtitle.needsExercises)
        #expect(subtitle.text == "No exercises · Not done yet")
        #expect(subtitle.spokenText == "Needs exercises, Not done yet")
    }

    @Test func templateThatCannotStartKeepsItsLastDoneDate() {
        let subtitle = WorkoutListRules.subtitle(
            exerciseCount: 0, canStart: false, lastPerformed: oct12, locale: enGB, timeZone: utc)
        #expect(subtitle.text == "No exercises · Last done 12 Oct 2026")
        #expect(subtitle.spokenText == "Needs exercises, Last done 12 Oct 2026")
    }

    // MARK: Path

    @Test func deletingTheOpenWorkoutPopsIt() {
        let id = UUID()
        #expect(WorkoutListRules.path(afterDeleting: id, from: [id]).isEmpty)
    }

    @Test func deletingRemovesEverythingFromItsScreenOn() {
        let first = UUID()
        let second = UUID()
        #expect(WorkoutListRules.path(afterDeleting: second, from: [first, second]) == [first])
        #expect(WorkoutListRules.path(afterDeleting: first, from: [first, second]).isEmpty)
    }

    @Test func deletingSomethingNotInThePathChangesNothing() {
        let open = UUID()
        #expect(WorkoutListRules.path(afterDeleting: UUID(), from: [open]) == [open])
        #expect(WorkoutListRules.path(afterDeleting: UUID(), from: []).isEmpty)
    }
}
