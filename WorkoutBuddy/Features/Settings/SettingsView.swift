import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage(AppSettings.Key.defaultReps) private var reps = AppSettings.Default.reps
    @AppStorage(AppSettings.Key.defaultKg) private var kg = AppSettings.Default.kg
    @AppStorage(AppSettings.Key.defaultRestSeconds) private var restSeconds = AppSettings.Default.restSeconds
    @AppStorage(AppSettings.Key.weightStep) private var weightStepRaw = AppSettings.Default.weightStep.rawValue
    @AppStorage(AppSettings.Key.soundEnabled) private var soundEnabled = AppSettings.Default.soundEnabled
    @AppStorage(AppSettings.Key.hapticsEnabled) private var hapticsEnabled = AppSettings.Default.hapticsEnabled

    // Bindings clamp on read and write, so a bad stored value is never shown or written back.
    private var repsBinding: Binding<Int> {
        Binding(get: { AppSettings.clampReps(reps) }, set: { reps = AppSettings.clampReps($0) })
    }

    private var kgBinding: Binding<Double> {
        Binding(get: { AppSettings.snapKg(kg) }, set: { kg = AppSettings.snapKg($0) })
    }

    private var restBinding: Binding<Int> {
        Binding(get: { AppSettings.clampRest(restSeconds) }, set: { restSeconds = AppSettings.clampRest($0) })
    }

    private var weightStepBinding: Binding<WeightStep> {
        Binding(
            get: { WeightStep(rawValue: weightStepRaw) ?? .default },
            set: { weightStepRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Library") {
                    NavigationLink("Exercises") { ExerciseListView() }
                }
                Section {
                    RepsStepper(reps: repsBinding)
                    WeightField(kg: kgBinding)
                    RestStepper(seconds: restBinding)
                } header: {
                    Text("Defaults for new sets")
                } footer: {
                    Text("Used for a new exercise\u{2019}s first set when the exercise has no defaults of its own and isn\u{2019}t in any saved workout.")
                }
                Section {
                    Picker("Weight Step", selection: weightStepBinding) {
                        ForEach(WeightStep.allCases) { step in
                            Text(step.displayName).tag(step)
                        }
                    }
                } footer: {
                    Text("How much the + and \u{2212} buttons change the weight.")
                }
                Section("Rest-end alert") {
                    Toggle("Sound", isOn: $soundEnabled)
                    Toggle("Haptics", isOn: $hapticsEnabled)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(ExercisePreviewData.container())
}
