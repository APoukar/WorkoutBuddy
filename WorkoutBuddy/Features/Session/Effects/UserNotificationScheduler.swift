import Foundation
import UserNotifications

/// The live `NotificationScheduling`: talks to `UNUserNotificationCenter`. It looks the center up in each
/// call and never stores it (it isn't `Sendable`), and passes only values across the protocol. The mapping
/// helpers are small pure functions, so they are unit tested; the calls to the center aren't.
/// There is no cancel guard here: the coordinator decides whether a cancel is safe.
@MainActor
struct UserNotificationScheduler: NotificationScheduling {
    /// The one rest-end notification's identifier; adding it again replaces the pending one.
    nonisolated static let identifier = "rest-end"

    /// The API refuses a trigger shorter than 1 second.
    nonisolated static let minimumTriggerInterval: TimeInterval = 1

    func schedule(_ request: RestNotificationRequest) async throws -> NotificationScheduleResult {
        // A rest with less than a second left (or already over) can't be scheduled.
        guard let interval = Self.triggerInterval(fireDate: request.fireDate, now: .now) else {
            return .tooLate
        }

        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.interruptionLevel = .active
        if let name = Self.soundFileName(for: request.sound) {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(name))
        }
        let notification = UNNotificationRequest(
            identifier: Self.identifier, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
        do {
            try await UNUserNotificationCenter.current().add(notification)
        } catch {
            throw Self.mapped(error)
        }
        return .added
    }

    func cancel() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }

    func removeDelivered() async {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }

    func authorization() async -> NotificationAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.authorization(for: settings.authorizationStatus)
    }

    func requestAuthorization() async throws {
        _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    // MARK: Pure helpers

    /// The bundled sound file for a sound choice; `nil` for no sound at all.
    nonisolated static func soundFileName(for sound: RestNotificationRequest.Sound) -> String? {
        switch sound {
        case .chime: "RestEnd.caf"
        case .silent: "RestEndSilent.caf"
        case .none: nil
        }
    }

    /// Seconds from `now` until `fireDate`; `nil` when less than the 1 s minimum is left (or it is past).
    /// Rounding up would fire the notification after the app has already ended the rest, a second alert.
    nonisolated static func triggerInterval(fireDate: Date, now: Date) -> TimeInterval? {
        let remaining = fireDate.timeIntervalSince(now)
        guard remaining >= minimumTriggerInterval else { return nil }
        return remaining
    }

    /// Undocumented `UNErrorDomain` code that `add` fails with when permission is denied or still undetermined
    /// ("Source is not authorized."). Seen on iOS 27; it isn't a `UNError.Code` case.
    nonisolated static let sourceNotAuthorizedErrorCode = 2003

    /// `UNError.notificationsNotAllowed` and the undocumented code 2003 become the app-level `.notAllowed`;
    /// any other error stays as it is.
    nonisolated static func mapped(_ error: Error) -> Error {
        if let unError = error as? UNError, unError.code == .notificationsNotAllowed {
            return NotificationSchedulingError.notAllowed
        }
        let nsError = error as NSError
        if nsError.domain == UNErrorDomain, nsError.code == sourceNotAuthorizedErrorCode {
            return NotificationSchedulingError.notAllowed
        }
        return error
    }

    /// Provisional and ephemeral authorization still deliver notifications, so they count as allowed.
    nonisolated static func authorization(for status: UNAuthorizationStatus) -> NotificationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .allowed
        @unknown default: .allowed
        }
    }
}
