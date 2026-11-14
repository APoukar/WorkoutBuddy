import SwiftUI

typealias ActivityState = WorkoutActivityAttributes.ContentState
typealias ActivityDisplayPhase = WorkoutActivityAttributes.DisplayPhase

/// The system count-up timer of the whole workout; it freezes at `pausedAt`. A `Text(timerInterval:)` takes
/// the widest string it could show, so the width is fixed instead (scaled with `style`). The accessibility label
/// is "Elapsed time, <running time>": the system flattens an island or platter into one element built from the
/// children's labels and drops their values, so the caption and the time both go into the label.
struct ElapsedTimerText: View {
    let state: ActivityState
    var font: Font
    @ScaledMetric private var width: Double

    init(state: ActivityState, font: Font = .subheadline, width: Double = 60,
         relativeTo style: Font.TextStyle = .subheadline) {
        self.state = state
        self.font = font
        _width = ScaledMetric(wrappedValue: width, relativeTo: style)
    }

    var body: some View {
        Text(timerInterval: state.elapsedStart...Date.distantFuture, pauseTime: state.pausedAt,
             countsDown: false, showsHours: true)
            .font(font.weight(.semibold))
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(width: width, alignment: .trailing)
            .accessibilityLabel(Text(WorkoutActivityStrings.elapsedTimeLabel) + Text(", ")
                + Text(timerInterval: state.elapsedStart...Date.distantFuture, pauseTime: state.pausedAt,
                       countsDown: false, showsHours: true))
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// The system countdown of the rest. It stops at 0:00 and stays there. The label is "Rest remaining,
/// <time>", built like `ElapsedTimerText`'s.
struct RestCountdownText: View {
    let restStart: Date
    let restEnd: Date
    var font: Font
    @ScaledMetric private var width: Double

    init(restStart: Date, restEnd: Date, font: Font = .title3, width: Double = 56,
         relativeTo style: Font.TextStyle = .title3) {
        self.restStart = restStart
        self.restEnd = restEnd
        self.font = font
        _width = ScaledMetric(wrappedValue: width, relativeTo: style)
    }

    var body: some View {
        Text(timerInterval: restStart...max(restStart, restEnd), pauseTime: nil, countsDown: true, showsHours: false)
            .font(font.weight(.semibold))
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(width: width, alignment: .trailing)
            .accessibilityLabel(Text(WorkoutActivityStrings.restRemainingLabel) + Text(", ")
                + Text(timerInterval: restStart...max(restStart, restEnd), pauseTime: nil, countsDown: true,
                       showsHours: false))
            .accessibilityAddTraits(.updatesFrequently)
    }
}
