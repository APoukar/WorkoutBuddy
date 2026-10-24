import SwiftData
import SwiftUI

/// The Workouts tab: all active templates by name, with the detail screen pushed on top.
struct WorkoutListView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Workout> { !$0.isSoftDeleted }) private var workouts: [Workout]

    /// IDs, not models: the destination looks the template up again, so a deleted one can't leave a dangling value.
    @State private var path: [UUID] = []
    @State private var creating = false
    @State private var pendingDeletion: Workout?
    @State private var failure: Error?

    private var library: WorkoutLibrary { WorkoutLibrary(context: context) }

    var body: some View {
        NavigationStack(path: $path) {
            List(WorkoutListRules.sortedByName(workouts)) { workout in
                NavigationLink(value: workout.id) { row(for: workout) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete") { pendingDeletion = workout }
                            .tint(.red)
                    }
            }
            .overlay {
                if workouts.isEmpty {
                    ContentUnavailableView {
                        Label("No Workouts", systemImage: "dumbbell")
                    } description: {
                        Text("Create a workout to plan your sets.")
                    } actions: {
                        Button("New Workout") { creating = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Workouts")
            .navigationDestination(for: UUID.self) { id in
                destination(for: id)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New Workout")
                }
            }
            .sheet(isPresented: $creating) { WorkoutEditorView(workout: nil) }
            .workoutDeletionAlert($pendingDeletion, library: library, onFailure: { failure = $0 })
            .errorAlert($failure, message: WorkoutMessages.failureMessage(for:))
        }
    }

    // MARK: Rows

    private func row(for workout: Workout) -> some View {
        let subtitle = WorkoutListRules.subtitle(
            exerciseCount: workout.exercises.filter { $0.exercise != nil }.count,
            canStart: library.canStart(workout),
            lastPerformed: library.lastPerformed(workout))
        return VStack(alignment: .leading, spacing: 2) {
            Text(workout.name)
            // Only the symbol is orange: the words stay in the secondary style for contrast, and the
            // warning doesn't rely on colour alone.
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if subtitle.needsExercises {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
                Text(subtitle.text)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(workout.name)
        .accessibilityValue(subtitle.spokenText)
    }

    // MARK: Destination

    @ViewBuilder
    private func destination(for id: UUID) -> some View {
        if let workout = library.workout(id: id) {
            WorkoutDetailView(workout: workout, onDeleted: { path = WorkoutListRules.path(afterDeleting: id, from: path) })
        } else {
            ContentUnavailableView("Workout Not Found", systemImage: "dumbbell")
        }
    }
}

#Preview("List") {
    WorkoutListView()
        .modelContainer(WorkoutPreviewData.container())
}

#Preview("Empty") {
    WorkoutListView()
        .modelContainer(ExercisePreviewData.container())
}
