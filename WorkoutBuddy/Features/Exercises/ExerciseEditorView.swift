import SwiftData
import SwiftUI

/// Add (`exercise == nil`) or edit an exercise.
struct ExerciseEditorView: View {
    let exercise: Exercise?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var muscleGroup: MuscleGroup
    @State private var hasEdited = false
    @State private var pendingDeletion: PendingExerciseDeletion?
    @State private var failure: Error?
    @FocusState private var nameFocused: Bool

    init(exercise: Exercise?) {
        self.exercise = exercise
        _name = State(initialValue: exercise?.name ?? "")
        _muscleGroup = State(initialValue: exercise?.muscleGroup ?? .chest)
    }

    private var library: ExerciseLibrary { ExerciseLibrary(context: context) }

    var body: some View {
        // Computed once per redraw.
        let nameError = library.validate(name: name, excluding: exercise)
        let shownError = ExerciseMessages.visibleNameError(nameError, hasEdited: hasEdited)
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
            .exerciseErrorAlert($failure)
        }
    }

    private func save() {
        do {
            if let exercise {
                try library.update(exercise, name: name, muscleGroup: muscleGroup)
            } else {
                try library.add(name: name, muscleGroup: muscleGroup)
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
