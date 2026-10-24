import Foundation
import Testing
@testable import WorkoutBuddy

struct WorkoutMessagesTests {
    @Test func nameErrorMessages() {
        #expect(WorkoutMessages.message(for: .empty) == "Enter a name.")
        #expect(WorkoutMessages.message(for: .duplicate) == "A workout with this name already exists.")
    }

    @Test func failureMessageUsesNameMessageOrGenericText() {
        #expect(WorkoutMessages.failureMessage(for: NameError.duplicate) == WorkoutMessages.message(for: .duplicate))
        #expect(WorkoutMessages.failureMessage(for: NameError.empty) == "Enter a name.")
        #expect(WorkoutMessages.failureMessage(for: WorkoutSaveError.invalid) == "Something went wrong. Please try again.")
        #expect(WorkoutMessages.failureMessage(for: WorkoutSaveError.missingExercise) == "Something went wrong. Please try again.")
        #expect(WorkoutMessages.failureMessage(for: NSError(domain: "X", code: 1)) == "Something went wrong. Please try again.")
    }

    @Test func issueMessages() {
        #expect(WorkoutMessages.message(for: DraftIssue.emptyName) == "Enter a name.")
        #expect(WorkoutMessages.message(for: DraftIssue.noExercises) == "Add at least one exercise.")
        #expect(WorkoutMessages.message(for: DraftIssue.exerciseWithoutSets) == "Every exercise needs at least one set.")
    }

    @Test func deleteConfirmationTexts() {
        #expect(WorkoutMessages.deleteTitle(workoutName: "Push") == "Delete \u{201C}Push\u{201D}?")
        #expect(WorkoutMessages.deleteMessage == "Past sessions stay in your history.")
    }
}
