import SwiftUI

/// The overlay shown over the set or rest screen while the workout is paused: a dimmed material, the
/// frozen elapsed time and the pinned Resume and End Workout buttons. Takes plain values and callbacks
/// only. End Workout only reports the tap; the owner decides what to ask and keeps the state. The
/// confirmation dialog is anchored to the End Workout button. Traps VoiceOver focus.
struct PausedOverlayView: View {
    let timer: ElapsedTimerInfo
    let onResume: () -> Void
    let onEnd: () -> Void
    /// The question being asked, owned by the caller.
    @Binding var confirmation: SessionConfirmation?
    let onConfirm: (SessionConfirmation) -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 64))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(SessionMessages.pausedTitle)
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                // Frozen: the timer has a `pauseTime`.
                ElapsedTimerText(
                    timer: timer, font: .system(.largeTitle, design: .rounded, weight: .semibold), alignment: .center)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .bottomActionBar {
            Button(action: onResume) {
                Text(SessionMessages.resumeButton).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)

            Button(role: .destructive, action: onEnd) {
                Text(SessionMessages.endButton).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier(UITestingContract.Identifier.pausedEndWorkout)
            .sessionConfirmation($confirmation, onConfirm: onConfirm)
        }
        .accessibilityAddTraits(.isModal)
    }
}

#Preview("Paused") {
    PausedOverlayView(
        timer: ElapsedTimerInfo(startedAt: .now.addingTimeInterval(-754), pausedDuration: 0, pausedAt: .now),
        onResume: {}, onEnd: {}, confirmation: .constant(nil), onConfirm: { _ in })
}

#Preview("Paused over a screen") {
    ZStack {
        SetScreenView(
            workoutName: "Push Day",
            timer: ElapsedTimerInfo(startedAt: .now.addingTimeInterval(-754), pausedDuration: 0, pausedAt: .now),
            setID: UUID(),
            exerciseName: "Bench Press",
            position: "Exercise 1 of 3 · Set 1 of 3",
            spokenPosition: "Exercise 1 of 3, set 1 of 3",
            initialReps: 10, initialKg: 62.5,
            nextText: "Next: Set 2 · 10 × 62.5 kg",
            spokenNextText: "Next: set 2, 10 reps at 62.5 kilograms",
            onDone: { _, _, _ in }, onSkip: { _ in }, onPause: {})
        PausedOverlayView(
            timer: ElapsedTimerInfo(startedAt: .now.addingTimeInterval(-754), pausedDuration: 0, pausedAt: .now),
            onResume: {}, onEnd: {}, confirmation: .constant(nil), onConfirm: { _ in })
    }
}

#Preview("Accessibility text size") {
    PausedOverlayView(
        timer: ElapsedTimerInfo(startedAt: .now.addingTimeInterval(-3_754), pausedDuration: 120, pausedAt: .now),
        onResume: {}, onEnd: {}, confirmation: .constant(nil), onConfirm: { _ in })
        .dynamicTypeSize(.accessibility3)
}
