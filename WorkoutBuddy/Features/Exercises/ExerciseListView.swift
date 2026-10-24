import SwiftData
import SwiftUI

/// Settings → Exercises. Pushed from Settings, so it has no `NavigationStack` of its own.
struct ExerciseListView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Exercise> { !$0.isArchived }) private var exercises: [Exercise]

    @State private var searchText = ""
    @State private var editor: EditorTarget?
    @State private var pendingDeletion: PendingExerciseDeletion?
    @State private var failure: Error?

    private enum EditorTarget: Identifiable {
        case add
        case edit(Exercise)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let exercise): exercise.id.uuidString
            }
        }
    }

    private var library: ExerciseLibrary { ExerciseLibrary(context: context) }

    var body: some View {
        let sections = ExerciseGrouping.grouped(exercises, matching: searchText)
        List {
            ForEach(sections) { section in
                Section(section.group.displayName) {
                    ForEach(section.exercises) { exercise in
                        Button { editor = .edit(exercise) } label: {
                            Text(exercise.name).foregroundStyle(Color.primary)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete") { requestDeletion(of: exercise) }
                                .tint(.red)
                        }
                    }
                }
            }
        }
        .overlay {
            if exercises.isEmpty {
                ContentUnavailableView("No Exercises", systemImage: "dumbbell", description: Text("Tap + to add one."))
            } else if sections.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .navigationTitle("Exercises")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editor = .add } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add Exercise")
            }
        }
        .sheet(item: $editor) { target in
            switch target {
            case .add: ExerciseEditorView(exercise: nil)
            case .edit(let exercise): ExerciseEditorView(exercise: exercise)
            }
        }
        .exerciseDeletionAlert(
            $pendingDeletion, library: library, onFailure: { failure = $0 })
        .exerciseErrorAlert($failure)
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

#Preview {
    NavigationStack { ExerciseListView() }
        .modelContainer(ExercisePreviewData.container())
}
