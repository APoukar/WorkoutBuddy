import SwiftData
import SwiftUI

/// Pushed inside the template editor's navigation stack. Tapping an exercise adds it and the picker stays open,
/// with the row turning "Added"; Back returns to the editor. It can't create exercises.
struct ExercisePickerView: View {
    /// Exercises already in the draft. An exercise can appear only once in a template.
    let addedExerciseIDs: Set<UUID>
    let onPick: (Exercise) -> Void

    @Query(filter: #Predicate<Exercise> { !$0.isArchived }) private var exercises: [Exercise]

    @State private var searchText = ""
    @State private var group: MuscleGroup?

    var body: some View {
        let sections = ExerciseGrouping.grouped(exercises, matching: searchText, in: group)
        let emptyState = ExercisePickerRules.emptyState(
            visibleCount: sections.reduce(0) { $0 + $1.exercises.count },
            inScopeCount: exercises.filter { group == nil || $0.muscleGroup == group }.count,
            searchText: searchText,
            group: group)
        List {
            ForEach(sections) { section in
                Section(section.group.displayName) {
                    ForEach(section.exercises) { exercise in
                        row(for: exercise)
                    }
                }
            }
        }
        .overlay { emptyOverlay(emptyState) }
        .navigationTitle("Add Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { filterMenu }
        }
    }

    private func row(for exercise: Exercise) -> some View {
        let isAdded = addedExerciseIDs.contains(exercise.id)
        return Button {
            onPick(exercise)
            AccessibilityNotification.Announcement(ExercisePickerRules.addedAnnouncement(for: exercise.name)).post()
        } label: {
            // LabeledContent moves "Added" below the name at accessibility text sizes.
            LabeledContent {
                if isAdded { Text("Added") }
            } label: {
                Text(exercise.name)
            }
            .foregroundStyle(isAdded ? Color.secondary : Color.primary)
            .contentShape(Rectangle())
        }
        .disabled(isAdded)
    }

    private var filterMenu: some View {
        Menu {
            Picker("Muscle Group", selection: $group) {
                Text(ExercisePickerRules.allGroupsTitle).tag(MuscleGroup?.none)
                ForEach(MuscleGroup.allCases, id: \.self) { option in
                    Text(option.displayName).tag(MuscleGroup?.some(option))
                }
            }
        } label: {
            Image(systemName: ExercisePickerRules.filterSymbol(for: group))
        }
        .accessibilityLabel(ExercisePickerRules.filterAccessibilityLabel)
        .accessibilityValue(ExercisePickerRules.filterAccessibilityValue(for: group))
    }

    @ViewBuilder
    private func emptyOverlay(_ state: ExercisePickerRules.EmptyState) -> some View {
        switch state {
        case .none:
            EmptyView()
        case .search(let text):
            ContentUnavailableView.search(text: text)
        case .noExercises(let group):
            ContentUnavailableView(
                "No Exercises", systemImage: "dumbbell",
                description: Text(ExercisePickerRules.noExercisesDescription(for: group)))
        }
    }
}

#Preview("Nothing added") {
    NavigationStack { ExercisePickerView(addedExerciseIDs: [], onPick: { _ in }) }
        .modelContainer(WorkoutPreviewData.container())
}

#Preview("Bench Press added") {
    let container = WorkoutPreviewData.container()
    let added = WorkoutPreviewData.exercise(named: "Bench Press", in: container).map { Set([$0.id]) } ?? []
    return NavigationStack { ExercisePickerView(addedExerciseIDs: added, onPick: { _ in }) }
        .modelContainer(container)
}
