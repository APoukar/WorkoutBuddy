import SwiftData
import SwiftUI

/// The sets of one exercise row in the template editor, pushed through `WorkoutEditorRoute.sets`.
/// Changes go straight into the editor's draft; Save in the editor commits them.
/// Every binding is built by set ID through the draft, never by array index, so a set that
/// disappears can't send a change to its neighbour.
struct ExerciseSetsView: View {
    @Binding var draft: WorkoutDraft
    /// The `DraftExercise.id` (the row in the draft), not the ID of the `Exercise` it points to.
    let draftExerciseID: UUID
    /// Looked up by the editor, so this view doesn't touch the model context on every edit.
    let title: String

    var body: some View {
        // Empty when the exercise isn't in the draft: the screen then shows nothing.
        let sets = draft.sets(ofExercise: draftExerciseID)
        Form {
            // Keyed by set ID: WeightField keeps its text in @State, which index keys would leave on the wrong set.
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                Section {
                    RepsStepper(reps: field(of: set, \.reps))
                    WeightField(kg: field(of: set, \.kg))
                    RestStepper(seconds: field(of: set, \.restSeconds))
                    if ExerciseSetsRules.showsDeleteSet(setCount: sets.count) {
                        Button("Delete Set", role: .destructive) {
                            withAnimation { draft.removeSet(set.id, fromExercise: draftExerciseID) }
                        }
                        .accessibilityLabel(ExerciseSetsRules.deleteAccessibilityLabel(forSetAt: index))
                    }
                } header: {
                    Text(ExerciseSetsRules.sectionTitle(forSetAt: index))
                }
            }
            if !sets.isEmpty {
                Section {
                    Button {
                        withAnimation { draft.addSet(toExercise: draftExerciseID) }
                    } label: {
                        Label("Add Set", systemImage: "plus.circle.fill")
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A binding to one value of one set, by ID. If the set is gone (for example while its row is
    /// animating out) it reads the last value it had and ignores writes.
    private func field<Value>(of set: DraftSet, _ keyPath: WritableKeyPath<SetValues, Value>) -> Binding<Value> {
        let setID = set.id
        let lastKnown = set.values[keyPath: keyPath]
        return Binding(
            get: { draft.values(ofSet: setID, inExercise: draftExerciseID)?[keyPath: keyPath] ?? lastKnown },
            set: { newValue in
                guard var values = draft.values(ofSet: setID, inExercise: draftExerciseID) else { return }
                values[keyPath: keyPath] = newValue
                draft.setValues(values, ofSet: setID, inExercise: draftExerciseID)
            })
    }
}

/// Holds a draft in `@State` so the previews can edit it.
private struct SetsPreview: View {
    let container: ModelContainer
    let rowID: UUID
    @State private var draft: WorkoutDraft

    init(sets: [SetValues]) {
        let container = WorkoutPreviewData.container()
        let bench = WorkoutPreviewData.exercise(named: "Bench Press", in: container)
        let row = DraftExercise(exerciseID: bench?.id ?? UUID(), sets: sets.map { DraftSet(values: $0) })
        self.container = container
        self.rowID = row.id
        _draft = State(initialValue: WorkoutDraft(name: "Push", exercises: [row]))
    }

    var body: some View {
        NavigationStack {
            ExerciseSetsView(draft: $draft, draftExerciseID: rowID, title: "Bench Press")
        }
        .modelContainer(container)
    }
}

#Preview("One set") {
    SetsPreview(sets: [SetValues(reps: 10, kg: 60, restSeconds: 90)])
}

#Preview("Three different sets") {
    SetsPreview(sets: [
        SetValues(reps: 12, kg: 40, restSeconds: 60),
        SetValues(reps: 8, kg: 60, restSeconds: 90),
        SetValues(reps: 5, kg: 80, restSeconds: 180),
    ])
}
