import Foundation

/// Why `SessionLibrary` refused an action. Pure, so `SessionMessages` can map it to a text.
nonisolated enum SessionError: Error, Equatable, Sendable {
    /// A session is already in progress (running or waiting for Save).
    case alreadyActive
    /// The template is soft-deleted or has nothing to run (see `WorkoutLibrary.canStart`).
    case cannotStart
}
