import Foundation
import UIKit
import UserNotifications

/// Decides how notifications show while the app is in the foreground (iOS asks only then, though on
/// iOS 18.2 it can call a moment after the app has left). For the `rest-end` notification the alert is
/// decided once, at delivery: when the app is active nothing is presented and the delegate plays the app's
/// own rest-end alert (unless the rest is no longer expected to alert, see below); in any other state (inactive, background) the system banner and the notification's
/// own sound are shown and nothing is played in-app (it would likely be silent). Anything else gets the
/// default banner, list and sound. A `rest-end` notification the app no longer expects (the user skipped
/// or paused the rest just before its fire date, and iOS had already handed the notification over) is
/// shown and played nowhere. `nonisolated`: the rule is a pure function, and reading the app state
/// and playing the alert hop to the main actor. `UNUserNotificationCenter.delegate` is weak, so
/// `LiveSessionEffects` keeps the strong reference.
nonisolated final class RestNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// What to do with a notification delivered in the foreground: the system presentation, and whether the
    /// app plays its own rest-end alert instead.
    struct Presentation: Equatable, Sendable {
        var options: UNNotificationPresentationOptions
        var playsInAppAlert: Bool
    }

    /// Asks whether a rest-end notification is still expected to alert. Read on the main actor when iOS
    /// hands a notification over, so it sees every user action reported before that moment.
    private let restEndIsExpected: @MainActor @Sendable () -> Bool

    init(restEndIsExpected: @escaping @MainActor @Sendable () -> Bool) {
        self.restEndIsExpected = restEndIsExpected
        super.init()
    }

    /// The rule (pure). For `rest-end`: not expected any more (`expected` is false) means nothing is shown
    /// or played; otherwise the in-app alert and no system presentation in an active app, the system
    /// banner and sound in any other state. Anything else gets the default presentation.
    static func presentation(
        identifier: String, appState: RestAlertRules.AppState, expected: Bool
    ) -> Presentation {
        guard identifier == UserNotificationScheduler.identifier else {
            return Presentation(options: [.banner, .list, .sound], playsInAppAlert: false)
        }
        guard expected else { return Presentation(options: [], playsInAppAlert: false) }
        if appState == .active { return Presentation(options: [], playsInAppAlert: true) }
        return Presentation(options: [.banner, .list, .sound], playsInAppAlert: false)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let identifier = notification.request.identifier
        let restEndIsExpected = restEndIsExpected
        return await MainActor.run {
            let presentation = Self.presentation(
                identifier: identifier, appState: .init(UIApplication.shared.applicationState),
                expected: restEndIsExpected())
            if presentation.playsInAppAlert { RestAlert.play() }  // Reads the Sound and Haptics settings itself.
            return presentation.options
        }
    }
}
