import Testing
@testable import WorkoutBuddy

struct ExerciseGroupingTests {
    private let sample = [
        Exercise(name: "Squat", muscleGroup: .legs),
        Exercise(name: "Row", muscleGroup: .back),
        Exercise(name: "Bench Press", muscleGroup: .chest),
        Exercise(name: "Dumbbell Fly", muscleGroup: .chest),
        Exercise(name: "Incline Press", muscleGroup: .chest),
        Exercise(name: "Thruster", muscleGroup: .fullBody),
    ]

    @Test func specOrderAndAlphabeticalNames() {
        let sections = ExerciseGrouping.grouped(sample, matching: "")
        #expect(sections.map(\.group) == [.chest, .back, .legs, .fullBody])
        #expect(sections[0].exercises.map(\.name) == ["Bench Press", "Dumbbell Fly", "Incline Press"])
    }

    @Test func groupFilter() {
        let sections = ExerciseGrouping.grouped(sample, matching: "", in: .legs)
        #expect(sections.map(\.group) == [.legs])
        #expect(ExerciseGrouping.grouped(sample, matching: "", in: .core).isEmpty)
    }

    @Test func searchMatching() {
        let sections = ExerciseGrouping.grouped(sample, matching: "PRESS")
        #expect(sections.flatMap(\.exercises).map(\.name) == ["Bench Press", "Incline Press"])
        #expect(ExerciseGrouping.grouped(sample, matching: "zzz").isEmpty)
        #expect(ExerciseGrouping.grouped(sample, matching: "press", in: .back).isEmpty)
    }

    @Test func emptyOrWhitespaceQueryMatchesAll() {
        #expect(ExerciseGrouping.grouped(sample, matching: "  ").flatMap(\.exercises).count == 6)
    }
}
