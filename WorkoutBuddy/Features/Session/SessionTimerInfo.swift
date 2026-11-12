import Foundation

/// What the system-rendered elapsed timer needs (`Text(timerInterval:pauseTime:countsDown:showsHours:)`).
/// Pure, so the intervals can be unit tested. The caller passes `pausedAt: nil` once the workout is
/// finished, since a finished workout is never shown as paused.
nonisolated struct ElapsedTimerInfo: Equatable, Sendable {
    var startedAt: Date
    var pausedDuration: TimeInterval
    var pausedAt: Date?

    /// Starts at `startedAt + pausedDuration`, so the timer shows the time spent working out. It has
    /// no real end; `pauseTime` freezes it while paused.
    var interval: ClosedRange<Date> {
        startedAt.addingTimeInterval(pausedDuration)...Date.distantFuture
    }
}

/// What the rest countdown needs: the system-rendered text and the progress ring.
nonisolated struct RestTimerInfo: Equatable, Sendable {
    /// When the rest ends (already moved later by a resume).
    var endsAt: Date
    /// The planned length of this rest, in seconds.
    var totalSeconds: Int
    /// Set while the workout is paused: the countdown and ring freeze at this moment.
    var pausedAt: Date?

    /// Counts down to `endsAt`. Its start is `endsAt - totalSeconds`, i.e. when the rest began.
    var interval: ClosedRange<Date> {
        endsAt.addingTimeInterval(-Double(max(totalSeconds, 0)))...endsAt
    }

    /// Whole seconds left at `pausedAt`, rounded up like `SessionSnapshot.restRemaining`, at least 0.
    /// The system countdown text doesn't freeze when paused, so the paused screen shows this instead.
    /// 0 when not paused.
    var frozenRemainingSeconds: Int {
        guard let pausedAt else { return 0 }
        return max(0, Int(endsAt.timeIntervalSince(pausedAt).rounded(.up)))
    }

    /// The share of the rest still left, from 1 (just started) to 0 (over). 0 for a rest with no length.
    func progress(at now: Date) -> Double {
        guard totalSeconds > 0 else { return 0 }
        let moment = pausedAt ?? now
        let remaining = endsAt.timeIntervalSince(moment)
        return min(max(remaining / Double(totalSeconds), 0), 1)
    }
}
