import SwiftData
import SwiftUI

/// A template's exercises and planned sets, with Edit and a pinned Start Workout button.
struct WorkoutDetailView: View {
    let workout: Workout
    /// Called once the editor sheet is gone after the template was deleted from it, so the caller can pop this screen.
    var onDeleted: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var editing = false
    /// Set by the editor when it deleted the template. Checked when the sheet has dismissed, so the pop
    /// happens once, after the sheet is gone, not underneath it.
    @State private var deletedInEditor = false
    @State private var error: Error?

    private var library: WorkoutLibrary { WorkoutLibrary(context: context) }

    /// Rows whose exercise is missing are skipped, as in the editor.
    private var rows: [WorkoutExercise] {
        workout.orderedExercises.filter { $0.exercise != nil }
    }

    var body: some View {
        let rows = rows
        let canStart = library.canStart(workout)
        Group {
            if rows.isEmpty {
                ContentUnavailableView {
                    Label("No Exercises", systemImage: "dumbbell")
                } description: {
                    Text("Edit this workout to add exercises.")
                }
            } else {
                List {
                    ForEach(rows) { row in
                        Section(row.exercise?.name ?? "") {
                            ForEach(Array(row.orderedSets.enumerated()), id: \.element.id) { index, set in
                                setRow(index: index, set: set)
                            }
                        }
                    }
                }
            }
        }
        .bottomActionBar {
            Button {
                start()
            } label: {
                Text("Start Workout").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!WorkoutDetailRules.isStartEnabled(canStart: canStart, isSoftDeleted: workout.isSoftDeleted))
            if !canStart {
                Text(WorkoutDetailRules.cannotStartHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = true }
            }
        }
        .errorAlert($error, message: SessionMessages.failureMessage(for:))
        .sheet(isPresented: $editing, onDismiss: editorDismissed) {
            WorkoutEditorView(workout: workout, onDeleted: { deletedInEditor = true })
        }
    }

    @ViewBuilder
    private func setRow(index: Int, set: PlannedSet) -> some View {
        let values = SetValues(reps: set.reps, kg: set.kg, restSeconds: set.restSeconds)
        let title = Text(ExerciseSetsRules.sectionTitle(forSetAt: index))
        let summary = Text(SetSummary.line(values))
        let rest = Label(Formatters.rest(seconds: set.restSeconds), systemImage: "timer")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Too wide for two columns: stack the row.
                VStack(alignment: .leading, spacing: 2) {
                    title
                    summary
                    rest
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    title
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        summary
                        rest
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WorkoutDetailRules.setAccessibilityLabel(forSetAt: index, values: values))
    }

    /// Starts a session. The full-screen session follows from the store (`RootTabView`), so there's nothing
    /// to present here.
    private func start() {
        let sessions = SessionLibrary(context: context)
        do {
            try sessions.start(workout)
            // The first successful Start asks for notification permission (live effects only ask while undetermined).
            sessions.effects.requestNotificationPermissionIfNeeded()
        } catch SessionError.alreadyActive {
            // A second tap while the session is opening. An alert here would knock the full-screen
            // session away, so it's logged only.
            ErrorLogging.log(SessionError.alreadyActive, action: "Start workout (already active)", category: "session")
        } catch {
            ErrorLogging.log(error, action: "Start workout", category: "session")
            self.error = error
        }
    }

    private func editorDismissed() {
        guard deletedInEditor else { return }
        deletedInEditor = false
        onDeleted()
    }
}

private struct DetailPreview: View {
    let name: String
    let container = WorkoutPreviewData.container()

    var body: some View {
        NavigationStack {
            if let workout = WorkoutPreviewData.workout(named: name, in: container) {
                WorkoutDetailView(workout: workout)
            }
        }
        .modelContainer(container)
    }
}

#Preview("Push Day") { DetailPreview(name: "Push Day") }

#Preview("Core (Bodyweight)") { DetailPreview(name: "Core") }

#Preview("Empty") { DetailPreview(name: "Empty") }
