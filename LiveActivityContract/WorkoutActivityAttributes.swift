import ActivityKit
import Foundation

/// The Live Activity of a workout session, shared by the app (which starts and updates it) and the widget
/// extension (which draws it). This folder is a member of both targets.
///
/// A stub for now: phase 4, step 6 adds the real content state.
nonisolated struct WorkoutActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var workoutName: String
    }

    /// The session this activity belongs to.
    var sessionID: UUID
}
