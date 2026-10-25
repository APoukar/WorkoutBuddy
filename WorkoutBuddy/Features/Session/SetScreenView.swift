import SwiftUI

/// The set screen: the exercise, the big reps and kg controls pre-filled for this set, a small "Next"
/// preview and the pinned Done and Skip Set buttons. Takes plain values and callbacks only. The reps
/// and kg are view state until Done and reset for each new set. Done and Skip report the ID of the set
/// they were shown for, so a stale screen can't act on a later set.
struct SetScreenView: View {
    let workoutName: String
    let timer: ElapsedTimerInfo
    let setID: UUID
    let exerciseName: String
    let position: String
    let spokenPosition: String
    let initialReps: Int
    let initialKg: Double
    let nextText: String
    let spokenNextText: String
    let onDone: (_ setID: UUID, _ reps: Int, _ kg: Double) -> Void
    let onSkip: (_ setID: UUID) -> Void
    let onPause: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SessionHeaderView(workoutName: workoutName, timer: timer, onPause: onPause)
            // Keyed by the set, so the reps and kg start over from the next set's pre-fill.
            SetEditor(
                setID: setID,
                exerciseName: exerciseName,
                position: position,
                spokenPosition: spokenPosition,
                initialReps: initialReps,
                initialKg: initialKg,
                nextText: nextText,
                spokenNextText: spokenNextText,
                onDone: onDone,
                onSkip: onSkip)
            .id(setID)
        }
    }
}

/// The scrolling content and the pinned buttons. Holds the edited reps and kg.
private struct SetEditor: View {
    let setID: UUID
    let exerciseName: String
    let position: String
    let spokenPosition: String
    let nextText: String
    let spokenNextText: String
    let onDone: (UUID, Int, Double) -> Void
    let onSkip: (UUID) -> Void

    @State private var reps: Int
    @State private var kg: Double

    init(
        setID: UUID, exerciseName: String, position: String, spokenPosition: String,
        initialReps: Int, initialKg: Double, nextText: String, spokenNextText: String,
        onDone: @escaping (UUID, Int, Double) -> Void, onSkip: @escaping (UUID) -> Void
    ) {
        self.setID = setID
        self.exerciseName = exerciseName
        self.position = position
        self.spokenPosition = spokenPosition
        self.nextText = nextText
        self.spokenNextText = spokenNextText
        self.onDone = onDone
        self.onSkip = onSkip
        _reps = State(initialValue: initialReps)
        _kg = State(initialValue: initialKg)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exerciseName)
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(position)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(spokenPosition)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                LargeRepsControl(reps: $reps)
                LargeWeightControl(kg: $kg)

                Text(nextText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(spokenNextText)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .bottomActionBar {
            Button {
                onDone(setID, reps, kg)
            } label: {
                Text(SessionMessages.doneButton).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)

            Button {
                onSkip(setID)
            } label: {
                Text(SessionMessages.skipSetButton).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

#Preview("Set") {
    SetScreenView(
        workoutName: "Push Day",
        timer: ElapsedTimerInfo(startedAt: .now.addingTimeInterval(-754), pausedDuration: 0, pausedAt: nil),
        setID: UUID(),
        exerciseName: "Bench Press",
        position: "Exercise 1 of 3 · Set 1 of 3",
        spokenPosition: "Exercise 1 of 3, set 1 of 3",
        initialReps: 10, initialKg: 62.5,
        nextText: "Next: Set 2 · 10 × 62.5 kg",
        spokenNextText: "Next: set 2, 10 reps at 62.5 kilograms",
        onDone: { _, _, _ in }, onSkip: { _ in }, onPause: {})
}

#Preview("Bodyweight, last set") {
    SetScreenView(
        workoutName: "Core",
        timer: ElapsedTimerInfo(startedAt: .now.addingTimeInterval(-3_754), pausedDuration: 0, pausedAt: nil),
        setID: UUID(),
        exerciseName: "Plank",
        position: "Exercise 2 of 2 · Set 3 of 3",
        spokenPosition: "Exercise 2 of 2, set 3 of 3",
        initialReps: 30, initialKg: 0,
        nextText: SessionMessages.lastSet,
        spokenNextText: SessionMessages.lastSet,
        onDone: { _, _, _ in }, onSkip: { _ in }, onPause: {})
}

#Preview("Long name") {
    SetScreenView(
        workoutName: "Upper Body Hypertrophy and Mobility Day",
        timer: ElapsedTimerInfo(startedAt: .now.addingTimeInterval(-754), pausedDuration: 0, pausedAt: nil),
        setID: UUID(),
        exerciseName: "Incline Dumbbell Bench Press with Neutral Grip",
        position: "Exercise 4 of 12 · Set 2 of 4",
        spokenPosition: "Exercise 4 of 12, set 2 of 4",
        initialReps: 12, initialKg: 127.5,
        nextText: "Next: Overhead Triceps Extension with Rope · 12 × 27.5 kg",
        spokenNextText: "Next: Overhead Triceps Extension with Rope, 12 reps at 27.5 kilograms",
        onDone: { _, _, _ in }, onSkip: { _ in }, onPause: {})
}

#Preview("Accessibility text size") {
    SetScreenView(
        workoutName: "Push Day",
        timer: ElapsedTimerInfo(startedAt: .now.addingTimeInterval(-754), pausedDuration: 0, pausedAt: nil),
        setID: UUID(),
        exerciseName: "Bench Press",
        position: "Exercise 1 of 3 · Set 1 of 3",
        spokenPosition: "Exercise 1 of 3, set 1 of 3",
        initialReps: 10, initialKg: 62.5,
        nextText: "Next: Set 2 · 10 × 62.5 kg",
        spokenNextText: "Next: set 2, 10 reps at 62.5 kilograms",
        onDone: { _, _, _ in }, onSkip: { _ in }, onPause: {})
        .dynamicTypeSize(.accessibility3)
}
