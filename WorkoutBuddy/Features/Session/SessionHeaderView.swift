import SwiftUI

/// The strip at the top of the set and rest screens: the workout name, the elapsed time (rendered by
/// the system, so it ticks on the second without redraws) and a Pause button.
struct SessionHeaderView: View {
    let workoutName: String
    let timer: ElapsedTimerInfo
    let onPause: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(workoutName)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                ElapsedTimerText(timer: timer, font: .title3.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onPause) {
                Image(systemName: "pause.fill")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel(SessionMessages.pauseLabel)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
        // Keep the strip from squeezing the content at the largest text sizes.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

/// The overall workout timer. One accessibility element: "Elapsed time, 3:25", updating frequently.
struct ElapsedTimerText: View {
    let timer: ElapsedTimerInfo
    var font: Font = .title3.weight(.semibold)
    /// Show the small "Elapsed time" caption above the number.
    var showsCaption = true
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            if showsCaption {
                Text(SessionMessages.elapsedTimeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(timerInterval: timer.interval, pauseTime: timer.pausedAt, countsDown: false, showsHours: true)
                .font(font)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview("Header") {
    SessionHeaderView(
        workoutName: "Push Day",
        timer: ElapsedTimerInfo(startedAt: .now.addingTimeInterval(-754), pausedDuration: 0, pausedAt: nil),
        onPause: {})
}

#Preview("Header, accessibility text size") {
    SessionHeaderView(
        workoutName: "Upper Body Hypertrophy and Mobility Day",
        timer: ElapsedTimerInfo(startedAt: .now.addingTimeInterval(-3_754), pausedDuration: 120, pausedAt: nil),
        onPause: {})
        .dynamicTypeSize(.accessibility3)
}
