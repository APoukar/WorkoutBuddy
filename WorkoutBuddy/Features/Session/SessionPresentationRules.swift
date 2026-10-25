import Foundation

/// A session that was interrupted by a kill and needs an answer before the workout is shown: resume it, or
/// end and save it (discard it when no set is done). Pure, so it can be unit tested.
nonisolated struct PendingRecovery: Equatable, Sendable {
    let sessionID: UUID
    /// The workout's name from the reference (soft-deleted or not), `nil` when the reference is gone.
    let workoutName: String?
    /// Whether a set is done: End & Save is offered, otherwise Discard.
    let canSave: Bool

    var message: String { SessionMessages.recoveryMessage(workoutName: workoutName) }
}

/// When the full-screen session is shown, and what the launch check asks. Pure, so it can be unit tested.
nonisolated enum SessionPresentationRules {
    /// The session the full-screen cover shows, or `nil` for no cover. `firstSessionID` is the newest
    /// in-progress session. The cover waits for the launch check (so it can't flash up before the
    /// recovery alert) and for the recovery question to be answered.
    static func coverSessionID(launchCheckDone: Bool, recoveryPending: Bool, firstSessionID: UUID?) -> UUID? {
        guard launchCheckDone, !recoveryPending else { return nil }
        return firstSessionID
    }

    /// Whether the recovery alert shows: while a question is pending, except while an error alert is up
    /// (it comes back once the error is dismissed, so the user can retry or resume).
    static func showsRecoveryAlert(recovery: PendingRecovery?, hasError: Bool) -> Bool {
        recovery != nil && !hasError
    }

    /// The question to ask for the launch check's decision: only `.askResume` asks. For `.showSummary` and
    /// `.nothingToRecover` the cover simply follows the stored sessions.
    static func pendingRecovery(for decision: LaunchRecovery, sessionID: UUID, workoutName: String?) -> PendingRecovery? {
        switch decision {
        case .askResume(let canSave):
            PendingRecovery(sessionID: sessionID, workoutName: workoutName, canSave: canSave)
        case .showSummary, .nothingToRecover:
            nil
        }
    }
}
