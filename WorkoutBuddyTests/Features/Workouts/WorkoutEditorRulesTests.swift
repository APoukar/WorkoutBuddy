import Foundation
import Testing
@testable import WorkoutBuddy

struct WorkoutEditorRulesTests {
    private let values = SetValues(reps: 10, kg: 60, restSeconds: 90)

    private func validDraft() -> WorkoutDraft {
        var draft = WorkoutDraft(name: "Push")
        draft.addExercise(exerciseID: UUID(), firstSet: values)
        return draft
    }

    // MARK: canSave

    @Test func canSaveWithValidNameAndExercise() {
        #expect(WorkoutEditorRules.canSave(validDraft(), nameError: nil))
    }

    @Test func cannotSaveWithNameError() {
        #expect(!WorkoutEditorRules.canSave(validDraft(), nameError: .duplicate))
        #expect(!WorkoutEditorRules.canSave(validDraft(), nameError: .empty))
    }

    @Test func cannotSaveWithoutExercises() {
        #expect(!WorkoutEditorRules.canSave(WorkoutDraft(name: "Empty"), nameError: nil))
    }

    @Test func cannotSaveWithBlankName() {
        var draft = validDraft()
        draft.name = "   "
        #expect(!WorkoutEditorRules.canSave(draft, nameError: nil))
    }

    @Test func cannotSaveWithExerciseWithoutSets() {
        var draft = validDraft()
        draft.exercises[0].sets = []
        #expect(!WorkoutEditorRules.canSave(draft, nameError: nil))
    }

    // MARK: hasChanges

    @Test func identicalDraftsHaveNoChanges() {
        let draft = validDraft()
        #expect(!WorkoutEditorRules.hasChanges(initial: draft, current: draft))
        #expect(!WorkoutEditorRules.hasChanges(initial: WorkoutDraft(), current: WorkoutDraft()))
    }

    @Test func renamingIsAChange() {
        let initial = validDraft()
        var current = initial
        current.name = "Pull"
        #expect(WorkoutEditorRules.hasChanges(initial: initial, current: current))
    }

    @Test func addingRemovingAndReorderingAreChanges() {
        var initial = validDraft()
        initial.addExercise(exerciseID: UUID(), firstSet: values)

        var added = initial
        added.addExercise(exerciseID: UUID(), firstSet: values)
        #expect(WorkoutEditorRules.hasChanges(initial: initial, current: added))

        var removed = initial
        removed.removeExercises(atOffsets: IndexSet(integer: 0))
        #expect(WorkoutEditorRules.hasChanges(initial: initial, current: removed))

        var moved = initial
        moved.moveExercise(id: moved.exercises[0].id, by: 1)
        #expect(WorkoutEditorRules.hasChanges(initial: initial, current: moved))
    }

    @Test func changingASetIsAChange() {
        let initial = validDraft()
        var current = initial
        let row = current.exercises[0]
        current.setValues(SetValues(reps: 12, kg: 60, restSeconds: 90), ofSet: row.sets[0].id, inExercise: row.id)
        #expect(WorkoutEditorRules.hasChanges(initial: initial, current: current))
    }

    @Test func undoingAChangeLeavesNoChanges() {
        let initial = validDraft()
        var current = initial
        current.name = "Pull"
        current.name = "Push"
        #expect(!WorkoutEditorRules.hasChanges(initial: initial, current: current))
    }

    // MARK: saveAction

    @Test func savingAnUnchangedExistingTemplateOnlyCloses() {
        #expect(WorkoutEditorRules.saveAction(hasChanges: false, isNew: false) == .closeOnly)
    }

    @Test func savingAChangedTemplateWrites() {
        #expect(WorkoutEditorRules.saveAction(hasChanges: true, isNew: false) == .write)
        #expect(WorkoutEditorRules.saveAction(hasChanges: true, isNew: true) == .write)
    }

    @Test func savingANewTemplateAlwaysWrites() {
        #expect(WorkoutEditorRules.saveAction(hasChanges: false, isNew: true) == .write)
    }

    // MARK: footerIssue

    @Test func footerShowsOnlyNoExercises() {
        #expect(WorkoutEditorRules.footerIssue(for: WorkoutDraft(name: "Empty")) == .noExercises)
        // A blank name alone is shown by the name field, not the footer.
        var blankName = validDraft()
        blankName.name = ""
        #expect(WorkoutEditorRules.footerIssue(for: blankName) == nil)
        #expect(WorkoutEditorRules.footerIssue(for: validDraft()) == nil)
    }

    @Test func footerIgnoresExerciseWithoutSets() {
        var draft = validDraft()
        draft.exercises[0].sets = []
        #expect(WorkoutEditorRules.footerIssue(for: draft) == nil)
    }

    @Test func footerShowsNoExercisesEvenWithBlankName() {
        #expect(WorkoutEditorRules.footerIssue(for: WorkoutDraft()) == .noExercises)
    }

    // MARK: Route

    @Test func routesAreHashableByCase() {
        let id = UUID()
        #expect(WorkoutEditorRoute.sets(draftExerciseID: id) == .sets(draftExerciseID: id))
        #expect(WorkoutEditorRoute.sets(draftExerciseID: id) != .sets(draftExerciseID: UUID()))
        #expect(WorkoutEditorRoute.sets(draftExerciseID: id) != .picker)
        #expect(Set([WorkoutEditorRoute.picker, .picker]).count == 1)
    }
}
