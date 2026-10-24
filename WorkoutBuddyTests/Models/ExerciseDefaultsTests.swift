import Testing
@testable import WorkoutBuddy

struct ExerciseDefaultsTests {
    @Test func noneHasNothingSet() {
        #expect(ExerciseDefaults.none == ExerciseDefaults(reps: nil, kg: nil, restSeconds: nil))
        #expect(ExerciseDefaults.none.clamped() == .none)
    }

    @Test func valuesInRangeStayUnchanged() {
        let defaults = ExerciseDefaults(reps: 8, kg: 62.5, restSeconds: 120)
        #expect(defaults.clamped() == defaults)
    }

    @Test func boundariesStayUnchanged() {
        let low = ExerciseDefaults(reps: 1, kg: 0, restSeconds: 0)
        let high = ExerciseDefaults(reps: 100, kg: 500, restSeconds: 600)
        #expect(low.clamped() == low)
        #expect(high.clamped() == high)
    }

    @Test func outOfRangeValuesAreClamped() {
        let tooLow = ExerciseDefaults(reps: 0, kg: -5, restSeconds: -30)
        #expect(tooLow.clamped() == ExerciseDefaults(reps: 1, kg: 0, restSeconds: 0))
        let tooHigh = ExerciseDefaults(reps: 500, kg: 900, restSeconds: 9000)
        #expect(tooHigh.clamped() == ExerciseDefaults(reps: 100, kg: 500, restSeconds: 600))
    }

    @Test func kgIsSnappedToHalfKilograms() {
        #expect(ExerciseDefaults(reps: nil, kg: 22.3, restSeconds: nil).clamped().kg == 22.5)
        #expect(ExerciseDefaults(reps: nil, kg: 22.2, restSeconds: nil).clamped().kg == 22)
        #expect(ExerciseDefaults(reps: nil, kg: .nan, restSeconds: nil).clamped().kg == 0)
    }

    @Test func eachValueIsClampedIndependentlyAndNilsStay() {
        let mixed = ExerciseDefaults(reps: 200, kg: nil, restSeconds: 90)
        #expect(mixed.clamped() == ExerciseDefaults(reps: 100, kg: nil, restSeconds: 90))
    }

    @Test @MainActor func exerciseDefaultsReadAndWriteTheFields() {
        let exercise = Exercise(name: "Squat", muscleGroup: .legs)
        #expect(exercise.defaults == .none)
        exercise.defaults = ExerciseDefaults(reps: 5, kg: 100, restSeconds: 180)
        #expect(exercise.defaultReps == 5 && exercise.defaultKg == 100 && exercise.defaultRestSeconds == 180)
        exercise.defaults = ExerciseDefaults(reps: nil, kg: 100, restSeconds: nil)
        #expect(exercise.defaultReps == nil && exercise.defaultKg == 100 && exercise.defaultRestSeconds == nil)
    }
}
