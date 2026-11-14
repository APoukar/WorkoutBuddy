import ActivityKit
import Foundation

/// The Live Activity of a workout session, shared by the app (which starts and updates it) and the widget
/// extension (which draws it). This folder is a member of both targets, so it may only use Foundation and
/// ActivityKit, never app types.
///
/// The content state carries ready-made texts plus the dates the system timers need, built in the app by
/// `LiveActivityContent`, so the widget needs no SwiftData, formatters or name lookups.
nonisolated struct WorkoutActivityAttributes: ActivityAttributes {
    /// What the session is doing, as the app knows it. A rest that has run out while the app was suspended
    /// is still `rest` here; the widget turns it into "Rest over" (see `ContentState.displayPhase(isStale:)`).
    nonisolated enum Phase: String, Codable, Hashable, Sendable {
        case set, rest, paused, finished
    }

    /// What the widget draws: the phases plus "Rest over", a rest seen after its stale date.
    nonisolated enum DisplayPhase: Equatable, Sendable {
        case set, rest, restOver, paused, finished
    }

    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var phase: Phase
        var workoutName: String
        /// The current set's exercise (during a rest: the next set's). `nil` when finished.
        var exerciseName: String? = nil
        /// "Exercise 2 of 5 · Set 3 of 4" and its spoken form. `nil` when finished.
        var position: String? = nil
        var spokenPosition: String? = nil
        /// "10 × 60 kg" / "10 × Bodyweight" of the current set (during a rest: the next set's), and its
        /// spoken form. `nil` when finished.
        var setLine: String? = nil
        var spokenSetLine: String? = nil
        /// The rest's "Up next" line and its spoken form. Only while a rest is running (not paused).
        var upNext: String? = nil
        var spokenUpNext: String? = nil
        /// Start of the system elapsed timer (`Text(timerInterval: elapsedStart...Date.distantFuture, pauseTime:)`).
        var elapsedStart: Date
        /// The moment the elapsed timer freezes. Only while paused.
        var pausedAt: Date? = nil
        /// The rest countdown's interval. Only while a rest is running (not paused).
        var restStart: Date? = nil
        var restEnd: Date? = nil
        /// The remaining rest as static text ("1:05"). Only when paused during a rest.
        var frozenRestText: String? = nil
        /// The summary's title and duration, and the duration's spoken form. Only when finished.
        var summaryTitle: String? = nil
        var durationText: String? = nil
        var spokenDurationText: String? = nil

        /// Which phase to draw: a rest seen after the activity went stale shows "Rest over".
        func displayPhase(isStale: Bool) -> DisplayPhase {
            switch phase {
            case .set: .set
            case .rest: isStale ? .restOver : .rest
            case .paused: .paused
            case .finished: .finished
            }
        }
    }

    /// The session this activity belongs to.
    var sessionID: UUID
}
