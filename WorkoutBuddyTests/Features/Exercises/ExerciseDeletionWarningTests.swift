import Testing
@testable import WorkoutBuddy

struct ExerciseDeletionWarningTests {
    @Test func noTemplates() {
        let w = ExerciseDeletionWarning.make(exerciseName: "Bench Press", templateNames: [])
        #expect(w.title == "Delete \u{201C}Bench Press\u{201D}?")
        #expect(w.message == "It stays in your history.")
    }

    @Test func twoTemplates() {
        let w = ExerciseDeletionWarning.make(exerciseName: "Squat", templateNames: ["Legs", "Push"])
        #expect(w.message == "It will be removed from Legs and Push.\n\nIt stays in your history.")
    }

    @Test func oneTemplateAndThree() {
        #expect(ExerciseDeletionWarning.make(exerciseName: "X", templateNames: ["A"]).message
            == "It will be removed from A.\n\nIt stays in your history.")
        #expect(ExerciseDeletionWarning.make(exerciseName: "X", templateNames: ["A", "B", "C"]).message
            == "It will be removed from A, B and C.\n\nIt stays in your history.")
    }

    @Test func uncappedWithEmptied() {
        let w = ExerciseDeletionWarning.make(exerciseName: "X", templateNames: ["Push", "Legs"], emptiedTemplateNames: ["Push"])
        #expect(w.message == "It will be removed from Push and Legs. Push will have no exercises left and can\u{2019}t be started until you add some.\n\nIt stays in your history.")
    }

    @Test func cappedWithEmptiedOutsideCap() {
        let w = ExerciseDeletionWarning.make(
            exerciseName: "X", templateNames: ["A", "B", "C", "D", "E"], emptiedTemplateNames: ["E"])
        #expect(w.message == "It will be removed from A, B, C and 2 more. E will have no exercises left and can\u{2019}t be started until you add some.\n\nIt stays in your history.")
    }

    @Test func twoEmptied() {
        let w = ExerciseDeletionWarning.make(exerciseName: "X", templateNames: ["Push", "Legs"], emptiedTemplateNames: ["Push", "Legs"])
        #expect(w.message == "It will be removed from Push and Legs. Push and Legs will have no exercises left and can\u{2019}t be started until you add some.\n\nIt stays in your history.")
    }

    @Test func emptiedNamesNotInTemplateListAreIgnored() {
        let w = ExerciseDeletionWarning.make(exerciseName: "X", templateNames: ["A"], emptiedTemplateNames: ["Ghost"])
        #expect(w.message == "It will be removed from A.\n\nIt stays in your history.")
    }
}
