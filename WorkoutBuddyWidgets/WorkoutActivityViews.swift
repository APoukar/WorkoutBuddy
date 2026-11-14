import SwiftUI
import WidgetKit

extension ActivityDisplayPhase {
    /// The symbol of the compact and minimal Dynamic Island.
    var symbolName: String {
        switch self {
        case .set, .restOver: "dumbbell.fill"
        case .rest: "timer"
        case .paused: "pause.fill"
        case .finished: "checkmark"
        }
    }
}

extension ActivityState {
    /// The running countdown's dates, if a rest is running and hasn't been paused.
    var restInterval: (start: Date, end: Date)? {
        guard let restStart, let restEnd else { return nil }
        return (restStart, restEnd)
    }
}

/// The Lock Screen content. iOS caps it at about 160 pt, so it has few rows: header + "Rest" row + progress bar +
/// up next while resting (4), header + exercise + position + set line (4), header + status + the set (5),
/// header + summary + duration (3). Takes the display phase as a parameter because previews can't show `isStale`.
struct WorkoutActivityContentView: View {
    let state: ActivityState
    let phase: ActivityDisplayPhase

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            switch phase {
            case .finished:
                finishedBody
            case .rest:
                restBody
            default:
                setBody
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(state.workoutName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if phase != .finished { ElapsedTimerText(state: state) }
        }
    }

    /// The current (after a rest: the next) set, with a status line above it where there is one.
    private var setBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            WorkoutActivityStatusLine(state: state, phase: phase)
            if let exerciseName = state.exerciseName {
                Text(exerciseName)
                    .font(.headline)
                    .lineLimit(1)
            }
            if let position = state.position {
                Text(position)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel(state.spokenPosition ?? position)
            }
            if let setLine = state.setLine {
                Text(setLine)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .accessibilityLabel(state.spokenSetLine ?? setLine)
            }
        }
    }

    /// The countdown, its progress bar and the "Up next" line.
    @ViewBuilder private var restBody: some View {
        if let interval = state.restInterval {
            HStack {
                Label(WorkoutActivityStrings.restTitle, systemImage: "timer")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                RestCountdownText(restStart: interval.start, restEnd: interval.end, font: .title3, width: 64)
            }
            WorkoutActivityRestProgress(interval: interval)
        }
        WorkoutActivityUpNextLine(state: state)
    }

    private var finishedBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(state.summaryTitle ?? "", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            if let durationText = state.durationText {
                Text(durationText)
                    .font(.subheadline.weight(.medium))
                    .accessibilityLabel(state.spokenDurationText ?? durationText)
            }
        }
    }
}

/// "Paused" (with the frozen rest time) or "Rest over"; nothing in the other phases.
struct WorkoutActivityStatusLine: View {
    let state: ActivityState
    let phase: ActivityDisplayPhase
    /// The Lock Screen has no leading symbol, so it shows one here; the expanded island already has one.
    var showsSymbol = true

    var body: some View {
        switch phase {
        case .paused:
            HStack {
                statusText(WorkoutActivityStrings.pausedTitle, symbol: "pause.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                if let frozen = state.frozenRestText {
                    Spacer(minLength: 8)
                    Text("\(WorkoutActivityStrings.restTitle) \(frozen)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .accessibilityLabel("\(WorkoutActivityStrings.restRemainingLabel) \(frozen)")
                }
            }
        case .restOver:
            statusText(WorkoutActivityStrings.restOverTitle, symbol: "bell.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private func statusText(_ title: String, symbol: String) -> some View {
        if showsSymbol {
            Label(title, systemImage: symbol)
        } else {
            Text(title)
        }
    }
}

struct WorkoutActivityRestProgress: View {
    let interval: (start: Date, end: Date)

    var body: some View {
        ProgressView(timerInterval: interval.start...max(interval.start, interval.end), countsDown: true) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .tint(.accentColor)
        .accessibilityHidden(true)
    }
}

/// "Up next  Bench Press · Set 4 · 10 × 60 kg" as one element; the label carries the spoken form (values get dropped when the system flattens the platter).
struct WorkoutActivityUpNextLine: View {
    let state: ActivityState

    var body: some View {
        if let upNext = state.upNext {
            HStack(spacing: 6) {
                Text(WorkoutActivityStrings.upNextTitle)
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
                Text(upNext)
            }
            .font(.footnote.weight(.medium))
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(WorkoutActivityStrings.upNextTitle), \(state.spokenUpNext ?? upNext)")
        }
    }
}

/// Expanded island, leading: the phase symbol and the workout name.
struct WorkoutActivityExpandedLeading: View {
    let state: ActivityState
    let phase: ActivityDisplayPhase

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: phase.symbolName)
                .accessibilityHidden(true)
            Text(state.workoutName)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
    }
}

/// Expanded island, trailing: the countdown during a rest, else the elapsed time (the duration when finished).
struct WorkoutActivityExpandedTrailing: View {
    let state: ActivityState
    let phase: ActivityDisplayPhase

    var body: some View {
        if phase == .rest, let interval = state.restInterval {
            RestCountdownText(restStart: interval.start, restEnd: interval.end, font: .title3, width: 64)
        } else if phase == .finished, let durationText = state.durationText {
            Text(durationText)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .accessibilityLabel(state.spokenDurationText ?? durationText)
        } else {
            ElapsedTimerText(state: state)
        }
    }
}

/// Expanded island, bottom, at most two lines: progress bar + up next while resting; exercise with set line and
/// position; "Rest over" or "Paused" with the exercise and set line; the summary when finished.
struct WorkoutActivityExpandedBottom: View {
    let state: ActivityState
    let phase: ActivityDisplayPhase

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch phase {
            case .rest:
                if let interval = state.restInterval { WorkoutActivityRestProgress(interval: interval) }
                WorkoutActivityUpNextLine(state: state)
            case .finished:
                Label(state.summaryTitle ?? "", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            case .paused, .restOver:
                WorkoutActivityStatusLine(state: state, phase: phase, showsSymbol: false)
                exerciseLine
            case .set:
                exerciseLine
                if let position = state.position {
                    Text(position)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityLabel(state.spokenPosition ?? position)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exerciseLine: some View {
        HStack(spacing: 8) {
            if let exerciseName = state.exerciseName {
                Text(exerciseName)
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let setLine = state.setLine {
                Text(setLine)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .layoutPriority(1)
                    .accessibilityLabel(state.spokenSetLine ?? setLine)
            }
        }
    }
}

/// The compact trailing view: the countdown during a rest, else the elapsed time (frozen text when finished).
struct WorkoutActivityCompactTrailing: View {
    let state: ActivityState
    let phase: ActivityDisplayPhase

    var body: some View {
        if phase == .rest, let interval = state.restInterval {
            RestCountdownText(restStart: interval.start, restEnd: interval.end, font: .body, width: 48, relativeTo: .body)
        } else if phase == .finished, let durationText = state.durationText {
            Text(durationText)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .accessibilityLabel(state.spokenDurationText ?? durationText)
        } else {
            ElapsedTimerText(state: state, font: .body, width: 64, relativeTo: .body)
        }
    }
}

/// The minimal view: the countdown during a rest, else the phase symbol.
struct WorkoutActivityMinimal: View {
    let state: ActivityState
    let phase: ActivityDisplayPhase

    var body: some View {
        if phase == .rest, let interval = state.restInterval {
            RestCountdownText(restStart: interval.start, restEnd: interval.end, font: .caption2, width: 40, relativeTo: .caption2)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(maxWidth: 40)
        } else {
            Image(systemName: phase.symbolName)
                .accessibilityHidden(true)
        }
    }
}
