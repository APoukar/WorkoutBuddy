import SwiftUI

/// The workout summary (F5): title, workout name, duration, set counts, total volume and the pinned
/// Save button. Without a done set it offers Discard Workout instead, with a note. Back to Workout goes
/// under either one. Takes plain values and callbacks only; Discard only reports the tap, and the owner
/// decides what to ask and keeps the state. The confirmation dialog is anchored to the Discard Workout
/// button. When finished sets can be looked at, a Review Sets row (and a swipe right) opens the review.
struct SessionSummaryView: View {
    let workoutName: String
    let content: SessionSummaryContent
    let onSave: () -> Void
    let onDiscard: () -> Void
    let onBackToWorkout: () -> Void
    /// The question being asked, owned by the caller.
    @Binding var confirmation: SessionConfirmation?
    let onConfirm: (SessionConfirmation) -> Void
    /// Opens the review of the newest finished set. `nil` when there's nothing to look at.
    var onReview: (() -> Void)?

    private var navigation: ReviewNavigation {
        ReviewNavigation(
            previous: onReview.map { ReviewNavigation.Action(title: SessionMessages.reviewSetsButton, perform: $0) })
    }

    var body: some View {
        List {
            // The title is part of the list, so it scrolls with it at large text sizes.
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.title)
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(workoutName)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .reviewAccessibilityActions(navigation)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                LabeledContent(SessionMessages.durationLabel) { Text(content.durationText) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(SessionMessages.durationLabel)
                    .accessibilityValue(content.spokenDurationText)
                LabeledContent(SessionMessages.volumeLabel) { Text(content.volumeText) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(SessionMessages.volumeLabel)
                    .accessibilityValue(content.spokenVolumeText)
            }
            Section(SessionMessages.setsLabel) {
                ForEach(content.counts, id: \.text) { line in
                    Text(line.text).accessibilityLabel(line.spokenText)
                }
            }
            if let onReview {
                Section {
                    Button(action: onReview) {
                        HStack {
                            Text(SessionMessages.reviewSetsButton)
                            Spacer()
                            Image(systemName: "chevron.forward")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            // Phase 6 adds the "New Records" section here.
        }
        .listStyle(.insetGrouped)
        .reviewSwipes(navigation)
        .accessibilityHiddenWhenCovered()
        .bottomActionBar {
            if content.canSave {
                Button(action: onSave) {
                    Text(SessionMessages.saveButton).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
            } else {
                Text(SessionMessages.cannotSaveNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(role: .destructive, action: onDiscard) {
                    Text(SessionMessages.discardButton).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                .accessibilityIdentifier(UITestingContract.Identifier.summaryDiscardWorkout)
                .sessionConfirmation($confirmation, onConfirm: onConfirm)
            }
            Button(action: onBackToWorkout) {
                Text(SessionMessages.backToWorkoutButton).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.extraLarge)
        }
    }
}

private func previewContent(
    done: Int, skipped: Int = 0, notPerformed: Int = 0, volume: Double, duration: TimeInterval
) -> SessionSummaryContent {
    let entries = (0..<(done + skipped + notPerformed)).map { index in
        let status: SetStatus = index < done ? .done : (index < done + skipped ? .skipped : .notPerformed)
        return SessionSnapshot.Entry(
            id: UUID(), exerciseIndex: 0, setIndex: index, exerciseID: nil,
            planned: SetValues(reps: 10, kg: 60, restSeconds: 90),
            actualReps: status == .done ? 10 : nil, actualKg: status == .done ? volume / Double(max(done, 1) * 10) : nil,
            status: status, completedAt: .now)
    }
    let start = Date(timeIntervalSince1970: 0)
    let snapshot = SessionSnapshot(
        startedAt: start, endedAt: start.addingTimeInterval(duration), exerciseCount: 1, entries: entries)
    return SessionSummaryContent(SessionStats(snapshot, now: start))
}

#Preview("Complete") {
    SessionSummaryView(
        workoutName: "Push Day", content: previewContent(done: 8, skipped: 1, volume: 4_250, duration: 3_900),
        onSave: {}, onDiscard: {}, onBackToWorkout: {}, confirmation: .constant(nil), onConfirm: { _ in })
}

#Preview("Ended early") {
    SessionSummaryView(
        workoutName: "Push Day", content: previewContent(done: 3, notPerformed: 5, volume: 1_800, duration: 1_500),
        onSave: {}, onDiscard: {}, onBackToWorkout: {}, confirmation: .constant(nil), onConfirm: { _ in })
}

#Preview("Nothing done") {
    SessionSummaryView(
        workoutName: "Upper Body Hypertrophy and Mobility Day",
        content: previewContent(done: 0, skipped: 4, volume: 0, duration: 45),
        onSave: {}, onDiscard: {}, onBackToWorkout: {}, confirmation: .constant(nil), onConfirm: { _ in })
}

#Preview("Accessibility text size") {
    SessionSummaryView(
        workoutName: "Push Day", content: previewContent(done: 8, skipped: 1, volume: 4_250, duration: 3_900),
        onSave: {}, onDiscard: {}, onBackToWorkout: {}, confirmation: .constant(nil), onConfirm: { _ in })
        .dynamicTypeSize(.accessibility3)
}

#Preview("With sets to review") {
    SessionSummaryView(
        workoutName: "Push Day", content: previewContent(done: 8, skipped: 1, volume: 4_250, duration: 3_900),
        onSave: {}, onDiscard: {}, onBackToWorkout: {}, confirmation: .constant(nil), onConfirm: { _ in },
        onReview: {})
}
