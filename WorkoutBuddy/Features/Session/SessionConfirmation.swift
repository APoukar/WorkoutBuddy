import Foundation

/// The confirmation asked before leaving a workout. Pure, so it can be unit tested.
nonisolated enum SessionConfirmation: Equatable, Sendable {
    /// End the workout early: the remaining sets are saved as not performed.
    case end
    /// Delete a workout in which no set was completed.
    case discard

    /// What End Workout asks: with a done set the workout can be ended and saved; without one it can only be discarded.
    static func forEndTap(in snapshot: SessionSnapshot) -> SessionConfirmation {
        snapshot.hasDoneSet ? .end : .discard
    }

    var title: String {
        switch self {
        case .end: SessionMessages.endTitle
        case .discard: SessionMessages.discardTitle
        }
    }

    var message: String {
        switch self {
        case .end: SessionMessages.endMessage
        case .discard: SessionMessages.discardMessage
        }
    }

    var confirmButton: String {
        switch self {
        case .end: SessionMessages.endButton
        case .discard: SessionMessages.discardButton
        }
    }
}
