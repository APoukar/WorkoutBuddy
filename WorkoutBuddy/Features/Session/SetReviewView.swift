import SwiftUI

/// A look back at an earlier set (done or skipped), shown as a layer above the live screen. A done
/// set's reps and kg can be corrected (every change is reported through `onEdit`, never on appear); a
/// skipped set can be marked as done with the values on screen, and a done set as skipped. Takes plain
/// values and callbacks only. The reps and kg are seeded once per set and never re-seeded from the
/// snapshot, so what the user typed stays. Edits to a skipped set are lost unless it is marked as done.
struct SetReviewView: View {
    let workoutName: String
    let timer: ElapsedTimerInfo
    /// `nil` from the summary: the time is frozen there, so there's no Pause.
    let onPause: (() -> Void)?
    let setID: UUID
    /// `.done` or `.skipped`.
    let status: SetStatus
    let exerciseName: String
    let position: String
    let spokenPosition: String
    let initialReps: Int
    let initialKg: Double
    /// "Back to Current Set" or "Back to Summary".
    let backTitle: String
    let hasPrevious: Bool
    /// At the newest set, Next acts as Back, like the swipe.
    let nextGoesBack: Bool
    /// The swipes are off while paused.
    let isPaused: Bool
    let onEdit: (_ setID: UUID, _ reps: Int, _ kg: Double) -> Void
    let onMarkDone: (_ setID: UUID, _ reps: Int, _ kg: Double) -> Void
    let onMarkSkipped: (_ setID: UUID) -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SessionHeaderView(workoutName: workoutName, timer: timer, onPause: onPause)
            ReviewEditor(
                setID: setID, status: status, exerciseName: exerciseName, position: position,
                spokenPosition: spokenPosition, initialReps: initialReps, initialKg: initialKg,
                backTitle: backTitle, hasPrevious: hasPrevious, nextGoesBack: nextGoesBack, isPaused: isPaused,
                onEdit: onEdit, onMarkDone: onMarkDone, onMarkSkipped: onMarkSkipped,
                onPrevious: onPrevious, onNext: onNext, onBack: onBack)
            .id(setID)
        }
    }
}

/// The editable content and the pinned buttons. Holds the edited reps and kg.
private struct ReviewEditor: View {
    let setID: UUID
    let status: SetStatus
    let exerciseName: String
    let position: String
    let spokenPosition: String
    let backTitle: String
    let hasPrevious: Bool
    let nextGoesBack: Bool
    let isPaused: Bool
    let onEdit: (UUID, Int, Double) -> Void
    let onMarkDone: (UUID, Int, Double) -> Void
    let onMarkSkipped: (UUID) -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onBack: () -> Void

    @State private var reps: Int
    @State private var kg: Double
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        setID: UUID, status: SetStatus, exerciseName: String, position: String, spokenPosition: String,
        initialReps: Int, initialKg: Double, backTitle: String, hasPrevious: Bool, nextGoesBack: Bool,
        isPaused: Bool,
        onEdit: @escaping (UUID, Int, Double) -> Void, onMarkDone: @escaping (UUID, Int, Double) -> Void,
        onMarkSkipped: @escaping (UUID) -> Void,
        onPrevious: @escaping () -> Void, onNext: @escaping () -> Void, onBack: @escaping () -> Void
    ) {
        self.setID = setID
        self.status = status
        self.exerciseName = exerciseName
        self.position = position
        self.spokenPosition = spokenPosition
        self.backTitle = backTitle
        self.hasPrevious = hasPrevious
        self.nextGoesBack = nextGoesBack
        self.isPaused = isPaused
        self.onEdit = onEdit
        self.onMarkDone = onMarkDone
        self.onMarkSkipped = onMarkSkipped
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onBack = onBack
        _reps = State(initialValue: initialReps)
        _kg = State(initialValue: initialKg)
    }

    private var navigation: ReviewNavigation {
        ReviewNavigation(
            isEnabled: !isPaused,
            previous: hasPrevious ? .init(title: SessionMessages.previousSetButton, perform: onPrevious) : nil,
            next: .init(title: nextGoesBack ? backTitle : SessionMessages.nextSetAction, perform: onNext))
    }

    var body: some View {
        SetEditorContent(
            exerciseName: exerciseName, position: position, spokenPosition: spokenPosition,
            reps: $reps, kg: $kg, navigation: navigation
        ) {
            statusBadge
        } footer: {
            if status == .done {
                Button {
                    onMarkSkipped(setID)
                } label: {
                    Text(SessionMessages.markAsSkippedButton).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        // Only a done set saves as it's edited. The change handlers don't run on appear.
        .onChange(of: reps) { _, newReps in
            if status == .done { onEdit(setID, newReps, kg) }
        }
        .onChange(of: kg) { _, newKg in
            if status == .done { onEdit(setID, reps, newKg) }
        }
        .bottomActionBar {
            if status == .skipped {
                Button {
                    onMarkDone(setID, reps, kg)
                } label: {
                    Text(SessionMessages.markAsDoneButton).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)

                backButton.buttonStyle(.bordered).controlSize(.large)
            } else {
                backButton.buttonStyle(.borderedProminent).controlSize(.extraLarge)
            }
            // At accessibility sizes the words would split and the bar would fill the screen: chevrons only.
            let iconOnly = dynamicTypeSize.isAccessibilitySize
            let nextLabel = nextGoesBack ? backTitle : SessionMessages.nextSetAction
            HStack(spacing: 8) {
                Button(action: onPrevious) {
                    Group {
                        if iconOnly {
                            Image(systemName: "chevron.backward")
                        } else {
                            Label(SessionMessages.previousButton, systemImage: "chevron.backward")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(!hasPrevious)
                .accessibilityLabel(SessionMessages.previousSetButton)
                .accessibilityInputLabels([SessionMessages.previousButton, SessionMessages.previousSetButton])

                Button(action: onNext) {
                    Group {
                        if iconOnly {
                            Image(systemName: "chevron.forward")
                        } else {
                            HStack(spacing: 6) {
                                Text(SessionMessages.nextButton)
                                Image(systemName: "chevron.forward")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(nextLabel)
                .accessibilityInputLabels([SessionMessages.nextButton, nextLabel])
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            Text(backTitle).frame(maxWidth: .infinity)
        }
    }

    /// Symbol and text, so the status isn't shown by colour alone.
    private var statusBadge: some View {
        let done = status == .done
        return Label(status.displayName, systemImage: done ? "checkmark.circle.fill" : "forward.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(done ? Color.green : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
    }
}

private let previewTimer = ElapsedTimerInfo(
    startedAt: .now.addingTimeInterval(-754), pausedDuration: 0, pausedAt: nil)
private let previewFrozenTimer = ElapsedTimerInfo(
    startedAt: .now.addingTimeInterval(-3_754), pausedDuration: 120, pausedAt: .now.addingTimeInterval(-60))

private func previewReview(
    status: SetStatus = .done, name: String = "Bench Press", reps: Int = 10, kg: Double = 62.5,
    fromSummary: Bool = false, hasPrevious: Bool = true
) -> SetReviewView {
    SetReviewView(
        workoutName: "Push Day",
        timer: fromSummary ? previewFrozenTimer : previewTimer,
        onPause: fromSummary ? nil : {},
        setID: UUID(), status: status, exerciseName: name,
        position: "Exercise 1 of 3 · Set 2 of 3", spokenPosition: "Exercise 1 of 3, set 2 of 3",
        initialReps: reps, initialKg: kg,
        backTitle: fromSummary ? SessionMessages.backToSummaryButton : SessionMessages.backToCurrentSetButton,
        hasPrevious: hasPrevious, nextGoesBack: !hasPrevious, isPaused: false,
        onEdit: { _, _, _ in }, onMarkDone: { _, _, _ in }, onMarkSkipped: { _ in },
        onPrevious: {}, onNext: {}, onBack: {})
}

#Preview("Done set") { previewReview() }
#Preview("Skipped set") { previewReview(status: .skipped) }
#Preview("Bodyweight") { previewReview(name: "Plank", reps: 30, kg: 0) }
#Preview("From the summary, oldest set") { previewReview(fromSummary: true, hasPrevious: false) }
#Preview("Long name") {
    previewReview(name: "Incline Dumbbell Bench Press with Neutral Grip", kg: 127.5)
}
#Preview("Accessibility text size") {
    previewReview(status: .skipped).dynamicTypeSize(.accessibility3)
}
