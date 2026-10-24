import Foundation
import Testing
@testable import WorkoutBuddy

struct FirstSetDefaultsTests {
    private let settings = AppSettings.Values(
        reps: 10, kg: 20, restSeconds: 90, weightStep: .twoAndHalf, soundEnabled: true, hapticsEnabled: true)
    private let lastUsed = SetValues(reps: 8, kg: 60, restSeconds: 120)

    @Test func everyValueComesFromTheExerciseWhenSet() {
        let own = ExerciseDefaults(reps: 5, kg: 100, restSeconds: 180)
        let result = FirstSetDefaults.resolve(exercise: own, lastUsed: lastUsed, settings: settings)
        #expect(result == SetValues(reps: 5, kg: 100, restSeconds: 180))
    }

    @Test func everyValueComesFromLastUsedWhenTheExerciseHasNoDefaults() {
        let result = FirstSetDefaults.resolve(exercise: .none, lastUsed: lastUsed, settings: settings)
        #expect(result == lastUsed)
    }

    @Test func everyValueComesFromSettingsWhenNothingElseIsAvailable() {
        let result = FirstSetDefaults.resolve(exercise: .none, lastUsed: nil, settings: settings)
        #expect(result == SetValues(reps: 10, kg: 20, restSeconds: 90))
    }

    @Test func sourcesMixPerValue() {
        // Last used supplies all three values or none: here reps come from the exercise,
        // kg and rest from last used.
        let own = ExerciseDefaults(reps: 5, kg: nil, restSeconds: nil)
        let withLastUsed = FirstSetDefaults.resolve(exercise: own, lastUsed: lastUsed, settings: settings)
        #expect(withLastUsed == SetValues(reps: 5, kg: 60, restSeconds: 120))

        // Without a last-used set, kg and rest come from Settings.
        let result = FirstSetDefaults.resolve(exercise: own, lastUsed: nil, settings: settings)
        #expect(result == SetValues(reps: 5, kg: 20, restSeconds: 90))

        let kgOnly = ExerciseDefaults(reps: nil, kg: 0, restSeconds: nil)
        let bodyweight = FirstSetDefaults.resolve(exercise: kgOnly, lastUsed: lastUsed, settings: settings)
        #expect(bodyweight == SetValues(reps: 8, kg: 0, restSeconds: 120))
    }
}
