import Testing
@testable import WorkoutBuddy

struct SettingsMessagesTests {
    @Test func footerExplainsTheBackgroundNotification() {
        #expect(SettingsMessages.restEndAlertFooter
            == "When the app is in the background, a notification alerts you: with the sound if Sound is on, or with a vibration if only Haptics is on.")
    }

    @Test func notificationRowTexts() {
        #expect(SettingsMessages.restEndAlertTitle == "Rest-end alert")
        #expect(SettingsMessages.notificationsOffTitle == "Notifications are off")
        #expect(SettingsMessages.openSettingsButton == "Open Settings")
        #expect(!SettingsMessages.openSettingsHint.isEmpty)
    }

    @Test(arguments: [
        (NotificationAuthorization.denied, true),
        (.notDetermined, false),
        (.allowed, false),
    ])
    func theNotificationsOffRowShowsOnlyWhenDenied(status: NotificationAuthorization, shows: Bool) {
        #expect(SettingsRules.showsNotificationsOffRow(for: status) == shows)
    }
}
