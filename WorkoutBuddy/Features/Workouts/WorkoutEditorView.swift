import SwiftData
import SwiftUI

/// Create (`workout == nil`) or edit a workout template, as a sheet. It edits a value-type
/// `WorkoutDraft`, never the models, so Cancel has nothing to undo and Save writes everything in one go.
struct WorkoutEditorView: View {
    let workout: Workout?
    /// Called after the template was deleted from this editor, just before the sheet dismisses.
    /// The caller decides what else to close (the list, the detail screen).
    var onDeleted: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var draft: WorkoutDraft
    /// The draft as the editor opened, to detect changes.
    @State private var initialDraft: WorkoutDraft
    @State private var path: [WorkoutEditorRoute] = []
    @State private var editMode: EditMode = .inactive
    @State private var hasEdited = false
    @State private var confirmingDiscard = false
    @State private var pendingDeletion: Workout?
    @State private var failure: Error?
    @FocusState private var nameFocused: Bool
    /// The name field takes focus on the first appearance only, not when popping back from a pushed screen.
    @State private var didAutofocus = false

    init(workout: Workout?, onDeleted: @escaping () -> Void = {}) {
        self.workout = workout
        self.onDeleted = onDeleted
        // Built once. A template always lives in a context; a new one starts empty.
        let initial = workout.flatMap { template in
            template.modelContext.map { WorkoutLibrary(context: $0).draft(for: template) }
        } ?? WorkoutDraft()
        _draft = State(initialValue: initial)
        _initialDraft = State(initialValue: initial)
    }

    private var library: WorkoutLibrary { WorkoutLibrary(context: context) }

    var body: some View {
        // Computed once per redraw.
        let nameError = library.validate(name: draft.name, excluding: workout)
        let shownError = NameRules.visibleError(nameError, hasEdited: hasEdited)
        let hasChanges = WorkoutEditorRules.hasChanges(initial: initialDraft, current: draft)
        NavigationStack(path: $path) {
            Form {
                nameSection(shownError: shownError)
                exercisesSection
                if workout != nil {
                    Section {
                        Button("Delete Workout", role: .destructive) { pendingDeletion = workout }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle(workout == nil ? "New Workout" : "Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: WorkoutEditorRoute.self) { destination(for: $0) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel(hasChanges: hasChanges) }
                        .confirmationDialog("Discard Changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                            Button("Discard Changes", role: .destructive) { dismiss() }
                            Button("Keep Editing", role: .cancel) {}
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(hasChanges: hasChanges) }
                        .disabled(!WorkoutEditorRules.canSave(draft, nameError: nameError))
                }
            }
            .onChange(of: draft.name) { hasEdited = true }
            .onChange(of: shownError) { _, new in
                if let new { AccessibilityNotification.Announcement(WorkoutMessages.message(for: new)).post() }
            }
            .onChange(of: draft.exercises.isEmpty) { _, isEmpty in
                if isEmpty { editMode = .inactive }
            }
            .onAppear {
                guard workout == nil, !didAutofocus else { return }
                didAutofocus = true
                nameFocused = true
            }
            .workoutDeletionAlert(
                $pendingDeletion, library: library, onFailure: { failure = $0 },
                onDeleted: {
                    onDeleted()
                    dismiss()
                })
            .errorAlert($failure, message: WorkoutMessages.failureMessage(for:))
        }
        // Swiping down would lose the changes without asking. See the plan's Decisions.
        .interactiveDismissDisabled(hasChanges)
    }

    // MARK: Sections

    private func nameSection(shownError: NameError?) -> some View {
        Section {
            TextField("Name", text: $draft.name)
                .focused($nameFocused)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
            if let shownError {
                Text(WorkoutMessages.message(for: shownError))
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var exercisesSection: some View {
        Section {
            ForEach(Array(draft.exercises.enumerated()), id: \.element.id) { index, row in
                // Looked up once per row, for both the visible and the accessibility label.
                let name = exerciseName(row.exerciseID)
                NavigationLink(value: WorkoutEditorRoute.sets(draftExerciseID: row.id)) {
                    exerciseRowLabel(row, name: name)
                }
                .accessibilityLabel(name)
                .accessibilityValue(SetSummary.spokenSummary(of: row.sets.map(\.values)))
                .accessibilityActions {
                    if index > 0 {
                        Button("Move Up") { draft.moveExercise(id: row.id, by: -1) }
                    }
                    if index < draft.exercises.count - 1 {
                        Button("Move Down") { draft.moveExercise(id: row.id, by: 1) }
                    }
                }
            }
            .onDelete { draft.removeExercises(atOffsets: $0) }
            .onMove { draft.moveExercises(fromOffsets: $0, toOffset: $1) }

            NavigationLink(value: WorkoutEditorRoute.picker) {
                Label("Add Exercise", systemImage: "plus.circle.fill")
            }
        } header: {
            HStack {
                Text("Exercises")
                Spacer()
                if !draft.exercises.isEmpty {
                    Button(editMode.isEditing ? "Done" : "Edit") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .textCase(nil)
                }
            }
        } footer: {
            if let issue = WorkoutEditorRules.footerIssue(for: draft) {
                Text(WorkoutMessages.message(for: issue))
            }
        }
    }

    private func exerciseRowLabel(_ row: DraftExercise, name: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
            Text(SetSummary.summary(of: row.sets.map(\.values)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// Names are always looked up. Archived exercises are found too.
    private func exerciseName(_ exerciseID: UUID) -> String {
        ExerciseLibrary(context: context).exercise(id: exerciseID)?.name ?? "Unknown Exercise"
    }

    // MARK: Destinations

    /// Placeholders until the exercise picker (step 8) and the sets screen (step 9) exist.
    @ViewBuilder
    private func destination(for route: WorkoutEditorRoute) -> some View {
        switch route {
        case .picker:
            ContentUnavailableView("Exercise Picker", systemImage: "list.bullet", description: Text("Coming soon."))
                .navigationTitle("Add Exercise")
                .navigationBarTitleDisplayMode(.inline)
        case .sets(let id):
            ContentUnavailableView("Sets", systemImage: "list.number", description: Text("Coming soon."))
                .navigationTitle(draft.exercises.first { $0.id == id }.map { exerciseName($0.exerciseID) } ?? "Sets")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Actions

    private func cancel(hasChanges: Bool) {
        if hasChanges {
            confirmingDiscard = true
        } else {
            dismiss()
        }
    }

    private func save(hasChanges: Bool) {
        guard WorkoutEditorRules.saveAction(hasChanges: hasChanges, isNew: workout == nil) == .write else {
            dismiss()
            return
        }
        do {
            try library.save(draft, to: workout)
            dismiss()
        } catch {
            ErrorLogging.log(error, action: "Saving workout", category: "workouts")
            failure = error
        }
    }
}

#Preview("New") {
    WorkoutEditorView(workout: nil)
        .modelContainer(WorkoutPreviewData.container())
}

#Preview("Edit Push Day") {
    let container = WorkoutPreviewData.container()
    return WorkoutEditorView(workout: WorkoutPreviewData.workout(named: "Push Day", in: container))
        .modelContainer(container)
}

#Preview("Edit Empty") {
    let container = WorkoutPreviewData.container()
    return WorkoutEditorView(workout: WorkoutPreviewData.workout(named: "Empty", in: container))
        .modelContainer(container)
}
