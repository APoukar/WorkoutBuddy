@preconcurrency import ActivityKit
import Foundation

/// The live `LiveActivityControlling`: talks to ActivityKit. It looks activities up in each call and never
/// stores them (`Activity` isn't `Sendable`), and passes only values across the protocol. The calls to
/// ActivityKit aren't unit tested.
@MainActor
struct ActivityKitController: LiveActivityControlling {
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func liveActivities() -> [LiveActivityInfo] {
        Activity<WorkoutActivityAttributes>.activities.compactMap { activity in
            guard Self.isLive(activity.activityState) else { return nil }
            return LiveActivityInfo(
                id: activity.id, sessionID: activity.attributes.sessionID,
                state: activity.content.state, staleDate: activity.content.staleDate)
        }
    }

    func request(sessionID: UUID, state: WorkoutActivityAttributes.ContentState, staleDate: Date?) async throws {
        do {
            _ = try Activity.request(
                attributes: WorkoutActivityAttributes(sessionID: sessionID),
                content: ActivityContent(state: state, staleDate: staleDate), pushType: nil)
        } catch {
            throw Self.mapped(error)
        }
    }

    func update(id: String, state: WorkoutActivityAttributes.ContentState, staleDate: Date?) async {
        guard let activity = Self.activity(id: id) else { return }
        await activity.update(ActivityContent(state: state, staleDate: staleDate))
    }

    func end(id: String) async {
        guard let activity = Self.activity(id: id) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    // MARK: Helpers

    private static func activity(id: String) -> Activity<WorkoutActivityAttributes>? {
        Activity<WorkoutActivityAttributes>.activities.first { $0.id == id }
    }

    /// Active, stale and pending activities count as existing; ended and dismissed ones are gone.
    private static func isLive(_ state: ActivityState) -> Bool {
        switch state {
        case .active, .stale: return true
        case .ended, .dismissed: return false
        default:
            // `.pending` is new in iOS 26 (it can't be named on the iOS 18 target without a check).
            if #available(iOS 26, *), state == .pending { return true }
            return false
        }
    }

    /// ActivityKit's "Live Activities are turned off" error becomes the app-level one; others stay.
    private static func mapped(_ error: Error) -> Error {
        if let error = error as? ActivityAuthorizationError, error == .denied {
            return LiveActivityError.notEnabled
        }
        return error
    }
}
