import Foundation

/// An expected, app-level failure of `NotificationScheduling.schedule`, so the pure layer needs no
/// `UserNotifications`. The live adapter maps `UNError.notificationsNotAllowed` to it; the coordinator
/// doesn't log it (it happens at every rest while permission is denied).
nonisolated enum NotificationSchedulingError: Error, Equatable, Sendable {
    case notAllowed
}

/// The notification center as the rest-end coordinator sees it. Values only, so the coordinator is unit
/// tested with a fake. The live adapter looks `UNUserNotificationCenter.current()` up per call.
/// There is one rest-end notification at a time; scheduling replaces the pending one.
@MainActor
protocol NotificationScheduling {
    /// Throws `NotificationSchedulingError.notAllowed` when permission is denied; other errors are logged.
    func schedule(_ request: RestNotificationRequest) async throws
    /// Removes the pending rest-end notification. The coordinator decides whether that is safe.
    func cancel() async
    /// Removes rest-end notifications already in Notification Center.
    func removeDelivered() async
    func authorization() async -> NotificationAuthorization
    func requestAuthorization() async throws
}
