import Foundation
import Testing
@testable import WorkoutBuddy

struct AppSettingsTests {
    /// Runs `body` with an isolated UserDefaults suite that is removed afterwards.
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    @Test func emptyDefaultsGiveDefaults() {
        withDefaults { defaults in
            let values = AppSettings.current(in: defaults)
            #expect(values.reps == 10)
            #expect(values.kg == 20)
            #expect(values.restSeconds == 90)
            #expect(values.weightStep == .twoAndHalf)
            #expect(values.soundEnabled)
            #expect(values.hapticsEnabled)
        }
    }

    @Test func storedValuesAreRead() {
        withDefaults { defaults in
            defaults.set(8, forKey: AppSettings.Key.defaultReps)
            defaults.set(42.5, forKey: AppSettings.Key.defaultKg)
            defaults.set(120, forKey: AppSettings.Key.defaultRestSeconds)
            defaults.set(WeightStep.one.rawValue, forKey: AppSettings.Key.weightStep)
            defaults.set(false, forKey: AppSettings.Key.soundEnabled)
            defaults.set(false, forKey: AppSettings.Key.hapticsEnabled)
            let values = AppSettings.current(in: defaults)
            #expect(values == .init(reps: 8, kg: 42.5, restSeconds: 120, weightStep: .one,
                                    soundEnabled: false, hapticsEnabled: false))
        }
    }

    @Test func outOfRangeValuesAreClamped() {
        withDefaults { defaults in
            defaults.set(0, forKey: AppSettings.Key.defaultReps)
            defaults.set(900.0, forKey: AppSettings.Key.defaultKg)
            defaults.set(-5, forKey: AppSettings.Key.defaultRestSeconds)
            var values = AppSettings.current(in: defaults)
            #expect(values.reps == 1)
            #expect(values.kg == 500)
            #expect(values.restSeconds == 0)

            defaults.set(1000, forKey: AppSettings.Key.defaultReps)
            defaults.set(-1.0, forKey: AppSettings.Key.defaultKg)
            defaults.set(9999, forKey: AppSettings.Key.defaultRestSeconds)
            values = AppSettings.current(in: defaults)
            #expect(values.reps == 100)
            #expect(values.kg == 0)
            #expect(values.restSeconds == 600)
        }
    }

    @Test func offGridKgIsSnapped() {
        withDefaults { defaults in
            defaults.set(22.3, forKey: AppSettings.Key.defaultKg)
            #expect(AppSettings.current(in: defaults).kg == 22.5)
        }
    }

    @Test func invalidWeightStepFallsBackToDefault() {
        withDefaults { defaults in
            defaults.set("1.25", forKey: AppSettings.Key.weightStep)
            #expect(AppSettings.current(in: defaults).weightStep == .twoAndHalf)
        }
    }

    @Test func weightStepValues() {
        #expect(WeightStep.allCases.map(\.kg) == [0.5, 1, 2.5])
        #expect(WeightStep.default == .twoAndHalf)
        #expect(WeightStep.default.kg == 2.5)
        #expect(WeightStep.allCases.allSatisfy { WeightStep(rawValue: $0.rawValue) == $0 })
        // Every step keeps weights on the 0.5 grid.
        #expect(WeightStep.allCases.allSatisfy { ($0.kg / AppSettings.kgGrid).truncatingRemainder(dividingBy: 1) == 0 })
    }

    @Test func clampHelpers() {
        #expect(AppSettings.clampReps(0) == 1)
        #expect(AppSettings.clampReps(101) == 100)
        #expect(AppSettings.clampRest(-1) == 0)
        #expect(AppSettings.clampRest(601) == 600)
    }
}
