import SwiftUI

/// The rest screen: a big countdown in a progress ring, the "Up next" set and the pinned Skip Rest and
/// Undo buttons. Takes plain values and callbacks only. The countdown text is rendered by the system
/// from `rest.endsAt`, so it stays exact without redraws. The screen doesn't advance by itself: the
/// owner does that when the rest ends.
struct RestScreenView: View {
    let workoutName: String
    let timer: ElapsedTimerInfo
    let rest: RestTimerInfo
    /// The done set Undo turns back to pending. `nil` disables Undo.
    let undoSetID: UUID?
    let upNext: String
    let spokenUpNext: String
    let onSkipRest: () -> Void
    let onUndo: (_ setID: UUID) -> Void
    let onPause: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SessionHeaderView(workoutName: workoutName, timer: timer, onPause: onPause)
            ScrollView {
                VStack(spacing: 24) {
                    Text(SessionMessages.restTitle)
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)

                    RestRing(rest: rest)
                        .frame(maxWidth: 320)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(SessionMessages.upNextTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(upNext)
                            .font(.title3.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(SessionMessages.upNextTitle)
                    .accessibilityValue(spokenUpNext)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .accessibilityHiddenWhenCovered()
        }
        .bottomActionBar {
            Button(action: onSkipRest) {
                Text(SessionMessages.skipRestButton).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)

            Button {
                if let undoSetID { onUndo(undoSetID) }
            } label: {
                Label(SessionMessages.undoButton, systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(undoSetID == nil)
        }
    }
}

/// The countdown number inside a circular progress ring. VoiceOver reads it as one element,
/// "Rest remaining, 1:30", updating frequently.
private struct RestRing: View {
    let rest: RestTimerInfo

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize = 72

    var body: some View {
        ZStack {
            ring
            VStack(spacing: 0) {
                // Above the number, so VoiceOver reads "Rest remaining" before the value.
                Text(SessionMessages.restRemainingCaption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(SessionMessages.restRemainingLabel)
                countdown
                    .font(.system(size: countdownSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
            }
            .padding(.horizontal, 32)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// The system countdown while running. It doesn't freeze with `pauseTime` when counting down, so
    /// while paused a static text shows the frozen remaining time.
    @ViewBuilder
    private var countdown: some View {
        if rest.pausedAt != nil {
            Text(Formatters.rest(seconds: rest.frozenRemainingSeconds))
        } else {
            Text(timerInterval: rest.interval, countsDown: true, showsHours: false)
        }
    }

    /// Redraws smoothly (or once a second with Reduce Motion), and not at all while paused.
    @ViewBuilder
    private var ring: some View {
        if rest.pausedAt != nil {
            RingShape(progress: rest.progress(at: .now))
        } else if reduceMotion {
            TimelineView(.periodic(from: rest.interval.lowerBound, by: 1)) { context in
                RingShape(progress: rest.progress(at: context.date))
            }
        } else {
            TimelineView(.animation) { context in
                RingShape(progress: rest.progress(at: context.date))
            }
        }
    }
}

/// A track with an arc on top that shrinks from the full circle as the rest runs down.
private struct RingShape: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 14)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(7)
        .accessibilityHidden(true)
    }
}

#Preview("Rest") {
    RestScreenView(
        workoutName: "Push Day",
        timer: ElapsedTimerInfo(startedAt: .now.addingTimeInterval(-754), pausedDuration: 0, pausedAt: nil),
        rest: RestTimerInfo(endsAt: .now.addingTimeInterval(62), totalSeconds: 90, pausedAt: nil),
        undoSetID: UUID(),
        upNext: "Bench Press · Set 2 · 10 × 62.5 kg",
        spokenUpNext: "Bench Press, set 2, 10 reps at 62.5 kilograms",
        onSkipRest: {}, onUndo: { _ in }, onPause: {})
}

#Preview("Bodyweight, long name") {
    RestScreenView(
        workoutName: "Upper Body Hypertrophy and Mobility Day",
        timer: ElapsedTimerInfo(startedAt: .now.addingTimeInterval(-3_754), pausedDuration: 0, pausedAt: nil),
        rest: RestTimerInfo(endsAt: .now.addingTimeInterval(605), totalSeconds: 900, pausedAt: nil),
        undoSetID: UUID(),
        upNext: "Incline Dumbbell Bench Press with Neutral Grip · Set 3 · 15 × Bodyweight",
        spokenUpNext: "Incline Dumbbell Bench Press with Neutral Grip, set 3, 15 reps, bodyweight",
        onSkipRest: {}, onUndo: { _ in }, onPause: {})
}

#Preview("Accessibility text size") {
    RestScreenView(
        workoutName: "Push Day",
        timer: ElapsedTimerInfo(startedAt: .now.addingTimeInterval(-754), pausedDuration: 0, pausedAt: nil),
        rest: RestTimerInfo(endsAt: .now.addingTimeInterval(62), totalSeconds: 90, pausedAt: nil),
        undoSetID: UUID(),
        upNext: "Bench Press · Set 2 · 10 × 62.5 kg",
        spokenUpNext: "Bench Press, set 2, 10 reps at 62.5 kilograms",
        onSkipRest: {}, onUndo: { _ in }, onPause: {})
        .dynamicTypeSize(.accessibility3)
}
