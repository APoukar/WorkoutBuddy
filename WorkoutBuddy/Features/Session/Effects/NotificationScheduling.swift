import Foundation

/// An expected, app-level failure of `NotificationScheduling.schedule`, so the pure layer needs no
/// `UserNotifications`. The live adapter maps `UNError.notificationsNotAllowed` to it; the coordinator
/// doesn't log it (it happens at every rest while permission is denied).
nonisolated enum NotificationSchedulingError: Error, Equatable, Sendable {
    case notAllowed
}

/// What `NotificationScheduling.schedule` did with a request.
nonisolated enum NotificationScheduleResult: Equatable, Sendable {
    /// The request is pending in the notification center.
    case added
    /// The fire date had already passed, so nothing was added. Not an error, but the rest isn't covered.
    case tooLate
}

/// The notification center as the rest-end coordinator sees it. Values only, so the coordinator is unit
/// tested with a fake. The live adapter looks `UNUserNotificationCenter.current()` up per call.
/// There is one rest-end notification at a time; scheduling replaces the pending one.
@MainActor
protocol NotificationScheduling {
    /// Throws `NotificationSchedulingError.notAllowed` when permission is denied; other errors are logged.
    /// Returns `.tooLate` (and adds nothing) when the fire date is too close or has passed.
    func schedule(_ request: RestNotificationRequest) async throws -> NotificationScheduleResult
    /// Removes the pending rest-end notification. The coordinator decides whether that is safe.
    func cancel() async
    /// Removes rest-end notifications already in Notification Center.
    func removeDelivered() async
    func authorization() async -> NotificationAuthorization
    func requestAuthorization() async throws
}
