import Foundation

/// User-facing texts and small rules for the Settings screen. Pure, so it can be unit tested.
nonisolated enum SettingsMessages {
    static let restEndAlertTitle = "Rest-end alert"

    /// Footer of the Rest-end alert section: what the notification does in the background, which depends
    /// on the Sound and Haptics toggles (Sound off + Haptics on uses a silent sound file so the phone vibrates).
    static let restEndAlertFooter =
        "When the app is in the background, a notification alerts you: with the sound if Sound is on, or with a vibration if only Haptics is on."

    static let notificationsOffTitle = "Notifications are off"
    static let openSettingsButton = "Open Settings"
    static let openSettingsHint = "Opens the notification settings for this app."
}

/// Which parts of Settings depend on the notification permission.
nonisolated enum SettingsRules {
    /// The "Notifications are off" row shows only after the user has denied permission. Before the prompt
    /// is answered (`.notDetermined`) there is nothing to fix yet.
    static func showsNotificationsOffRow(for authorization: NotificationAuthorization) -> Bool {
        authorization == .denied
    }
}
