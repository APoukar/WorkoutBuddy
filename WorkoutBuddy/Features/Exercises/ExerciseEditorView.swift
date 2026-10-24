import SwiftData
import SwiftUI

/// Add (`exercise == nil`) or edit an exercise.
struct ExerciseEditorView: View {
    let exercise: Exercise?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var muscleGroup: MuscleGroup
    // Each default is an on/off switch plus a value. The value is only stored while its switch is on.
    @State private var repsOn: Bool
    @State private var reps: Int
    @State private var kgOn: Bool
    @State private var kg: Double
    @State private var restOn: Bool
    @State private var restSeconds: Int
    @State private var hasEdited = false
    @State private var pendingDeletion: PendingExerciseDeletion?
    @State private var failure: Error?
    @FocusState private var nameFocused: Bool

    init(exercise: Exercise?) {
        self.exercise = exercise
        _name = State(initialValue: exercise?.name ?? "")
        _muscleGroup = State(initialValue: exercise?.muscleGroup ?? .chest)
        let defaults = exercise?.defaults ?? .none
        let settings = AppSettings.current()
        _repsOn = State(initialValue: defaults.reps != nil)
        _reps = State(initialValue: defaults.reps ?? settings.reps)
        _kgOn = State(initialValue: defaults.kg != nil)
        _kg = State(initialValue: defaults.kg ?? settings.kg)
        _restOn = State(initialValue: defaults.restSeconds != nil)
        _restSeconds = State(initialValue: defaults.restSeconds ?? settings.restSeconds)
    }

    private var defaults: ExerciseDefaults {
        ExerciseDefaults(
            reps: repsOn ? reps : nil, kg: kgOn ? kg : nil, restSeconds: restOn ? restSeconds : nil)
    }

    private var library: ExerciseLibrary { ExerciseLibrary(context: context) }

    var body: some View {
        // Computed once per redraw.
        let nameError = library.validate(name: name, excluding: exercise)
        let shownError = NameRules.visibleError(nameError, hasEdited: hasEdited)
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($nameFocused)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                    if let shownError {
                        Text(ExerciseMessages.message(for: shownError))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Picker("Muscle Group", selection: $muscleGroup) {
                        ForEach(MuscleGroup.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                Section {
                    Toggle("Custom Reps", isOn: $repsOn.animation())
                    if repsOn { RepsStepper(reps: $reps) }
                    Toggle("Custom Weight", isOn: $kgOn.animation())
                    if kgOn { WeightField(kg: $kg) }
                    Toggle("Custom Rest", isOn: $restOn.animation())
                    if restOn { RestStepper(seconds: $restSeconds) }
                } header: {
                    Text("Defaults for new sets")
                } footer: {
                    Text("Used for this exercise\u{2019}s first set when you add it to a workout. Values that are off come from the last workout you saved with this exercise, then from Settings.")
                }
                if let exercise {
                    Section {
                        Button("Delete Exercise", role: .destructive) { requestDeletion(of: exercise) }
                    }
                }
            }
            .navigationTitle(exercise == nil ? "New Exercise" : "Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(nameError != nil)
                }
            }
            .onChange(of: name) { hasEdited = true }
            .onChange(of: shownError) { _, new in
                if let new { AccessibilityNotification.Announcement(ExerciseMessages.message(for: new)).post() }
            }
            .onAppear { if exercise == nil { nameFocused = true } }
            .exerciseDeletionAlert(
                $pendingDeletion, library: library, onFailure: { failure = $0 }, onDeleted: { dismiss() })
            .errorAlert($failure, message: ExerciseMessages.failureMessage(for:))
        }
    }

    private func save() {
        do {
            if let exercise {
                try library.update(exercise, name: name, muscleGroup: muscleGroup, defaults: defaults)
            } else {
                try library.add(name: name, muscleGroup: muscleGroup, defaults: defaults)
            }
            dismiss()
        } catch {
            ErrorLogging.log(error, action: "Saving exercise", category: "exercises")
            failure = error
        }
    }

    private func requestDeletion(of exercise: Exercise) {
        do {
            pendingDeletion = try .make(for: exercise, library: library)
        } catch {
            ErrorLogging.log(error, action: "Preparing exercise deletion", category: "exercises")
            failure = error
        }
    }
}

#Preview("Add") {
    ExerciseEditorView(exercise: nil)
        .modelContainer(ExercisePreviewData.container())
}

#Preview("Edit Bench Press") {
    let container = ExercisePreviewData.container()
    return ExerciseEditorView(exercise: ExercisePreviewData.benchPress(in: container))
        .modelContainer(container)
}
