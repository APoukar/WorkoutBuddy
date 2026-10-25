import SwiftUI

/// The workout summary (F5): title, workout name, duration, set counts, total volume and the pinned
/// Save button. Without a done set it offers Discard Workout instead, with a note. Takes plain values
/// and callbacks only; Discard only reports the tap, and the owner decides what to ask and keeps the
/// state. The confirmation dialog is anchored to the Discard Workout button.
struct SessionSummaryView: View {
    let workoutName: String
    let content: SessionSummaryContent
    let onSave: () -> Void
    let onDiscard: () -> Void
    /// The question being asked, owned by the caller.
    @Binding var confirmation: SessionConfirmation?
    let onConfirm: (SessionConfirmation) -> Void

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
            // Phase 6 adds the "New Records" section here.
        }
        .listStyle(.insetGrouped)
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
                .sessionConfirmation($confirmation, onConfirm: onConfirm)
            }
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
        onSave: {}, onDiscard: {}, confirmation: .constant(nil), onConfirm: { _ in })
}

#Preview("Ended early") {
    SessionSummaryView(
        workoutName: "Push Day", content: previewContent(done: 3, notPerformed: 5, volume: 1_800, duration: 1_500),
        onSave: {}, onDiscard: {}, confirmation: .constant(nil), onConfirm: { _ in })
}

#Preview("Nothing done") {
    SessionSummaryView(
        workoutName: "Upper Body Hypertrophy and Mobility Day",
        content: previewContent(done: 0, skipped: 4, volume: 0, duration: 45),
        onSave: {}, onDiscard: {}, confirmation: .constant(nil), onConfirm: { _ in })
}

#Preview("Accessibility text size") {
    SessionSummaryView(
        workoutName: "Push Day", content: previewContent(done: 8, skipped: 1, volume: 4_250, duration: 3_900),
        onSave: {}, onDiscard: {}, confirmation: .constant(nil), onConfirm: { _ in })
        .dynamicTypeSize(.accessibility3)
}
