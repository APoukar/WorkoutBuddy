import Foundation
import Testing
@testable import WorkoutBuddy

struct ExerciseMessagesTests {
    @Test func nameErrorMessages() {
        #expect(ExerciseMessages.message(for: .empty) == "Enter a name.")
        #expect(ExerciseMessages.message(for: .duplicate) == "An exercise with this name already exists.")
    }

    @Test func failureMessageUsesNameMessageOrGenericText() {
        #expect(ExerciseMessages.failureMessage(for: NameError.duplicate) == ExerciseMessages.message(for: .duplicate))
        let generic = ExerciseMessages.failureMessage(for: NSError(domain: "X", code: 1))
        #expect(generic.contains("Please try again"))
    }
}
