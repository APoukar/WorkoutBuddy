import Foundation

/// What to do with the active session found when the app process starts. Pure, so it can be unit tested.
nonisolated enum LaunchRecovery: Equatable, Sendable {
    /// Nothing to recover: the session is already saved (or there is none).
    case nothingToRecover
    /// The workout was interrupted while running: ask whether to resume it. `canSave` is whether a set
    /// is done, i.e. whether End Workout is offered (otherwise Discard).
    case askResume(canSave: Bool)
    /// The workout is over and waiting for Save: reopen the summary without asking.
    case showSummary

    static func decide(_ snapshot: SessionSnapshot) -> LaunchRecovery {
        guard snapshot.status == .inProgress else { return .nothingToRecover }
        // Finished and waiting for Save. A session with no pending set but no `endedAt` (only bad data can
        // produce it) is treated the same: its Save ends it at the last activity.
        if snapshot.isFinished || snapshot.currentSetIndex == nil { return .showSummary }
        return .askResume(canSave: snapshot.hasDoneSet)
    }
}
