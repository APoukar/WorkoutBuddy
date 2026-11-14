import Foundation

/// An expected, app-level failure of `LiveActivityControlling.request`: the user turned Live Activities
/// off. The live adapter maps ActivityKit's error to it; the coordinator doesn't log it.
nonisolated enum LiveActivityError: Error, Equatable, Sendable {
    case notEnabled
}

/// A live Live Activity of this app, as plain values.
nonisolated struct LiveActivityInfo: Equatable, Sendable {
    var id: String
    var sessionID: UUID
    var state: WorkoutActivityAttributes.ContentState
    var staleDate: Date?
}

/// ActivityKit as the Live Activity coordinator sees it. Values only (an `Activity` isn't `Sendable`), so
/// the coordinator is unit tested with a fake. The live adapter looks activities up per call.
@MainActor
protocol LiveActivityControlling {
    /// Whether the user allows Live Activities for this app.
    var areActivitiesEnabled: Bool { get }
    /// The activities that still count: active, stale or pending. Ended and dismissed ones are left out.
    func liveActivities() -> [LiveActivityInfo]
    /// Throws `LiveActivityError.notEnabled` when Live Activities are turned off; other errors are logged.
    func request(sessionID: UUID, state: WorkoutActivityAttributes.ContentState, staleDate: Date?) async throws
    /// An update with a `nil` stale date makes a stale activity active again.
    func update(id: String, state: WorkoutActivityAttributes.ContentState, staleDate: Date?) async
    /// Ends the activity and removes it from the Lock Screen at once.
    func end(id: String) async
}
