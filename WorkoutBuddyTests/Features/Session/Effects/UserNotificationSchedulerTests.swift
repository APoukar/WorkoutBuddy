import Foundation
import Testing
import UserNotifications
@testable import WorkoutBuddy

/// The pure helpers of the live adapter and the delegate rule. Nothing here talks to the real notification center.
struct UserNotificationSchedulerTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func identifierIsRestEnd() {
        #expect(UserNotificationScheduler.identifier == "rest-end")
    }

    @Test func soundFileNames() {
        #expect(UserNotificationScheduler.soundFileName(for: .chime) == "RestEnd.caf")
        #expect(UserNotificationScheduler.soundFileName(for: .silent) == "RestEndSilent.caf")
        #expect(UserNotificationScheduler.soundFileName(for: .none) == nil)
    }

    @Test func bundledSoundFilesExist() {
        for sound in [RestNotificationRequest.Sound.chime, .silent] {
            let name = UserNotificationScheduler.soundFileName(for: sound) ?? ""
            let url = URL(fileURLWithPath: name)
            let file = url.deletingPathExtension().lastPathComponent
            #expect(Bundle.main.url(forResource: file, withExtension: url.pathExtension) != nil)
        }
    }

    @Test func triggerIntervalIsTheTimeUntilTheFireDate() {
        #expect(UserNotificationScheduler.triggerInterval(fireDate: now + 90, now: now) == 90)
        #expect(UserNotificationScheduler.triggerInterval(fireDate: now + 1.5, now: now) == 1.5)
    }

    @Test func triggerIntervalIsNilBelowTheOneSecondMinimum() {
        #expect(UserNotificationScheduler.triggerInterval(fireDate: now + 1, now: now) == 1)
        #expect(UserNotificationScheduler.triggerInterval(fireDate: now + 0.999, now: now) == nil)
        #expect(UserNotificationScheduler.triggerInterval(fireDate: now + 0.5, now: now) == nil)
        #expect(UserNotificationScheduler.triggerInterval(fireDate: now + 0.2, now: now) == nil)
    }

    @Test func triggerIntervalIsNilWhenTheFireDateIsPast() {
        #expect(UserNotificationScheduler.triggerInterval(fireDate: now, now: now) == nil)
        #expect(UserNotificationScheduler.triggerInterval(fireDate: now - 5, now: now) == nil)
    }

    @Test func notificationsNotAllowedMapsToTheAppError() {
        let mapped = UserNotificationScheduler.mapped(UNError(.notificationsNotAllowed))
        #expect(mapped as? NotificationSchedulingError == .notAllowed)
    }

    @Test func otherErrorsAreNotMapped() {
        let other = UserNotificationScheduler.mapped(UNError(.attachmentInvalidURL))
        #expect((other as? UNError)?.code == .attachmentInvalidURL)

        struct Failure: Error {}
        #expect(UserNotificationScheduler.mapped(Failure()) is Failure)
    }

    @Test func authorizationMapping() {
        let map = UserNotificationScheduler.authorization(for:)
        #expect(map(.notDetermined) == .notDetermined)
        #expect(map(.denied) == .denied)
        #expect(map(.authorized) == .allowed)
        #expect(map(.provisional) == .allowed)
        #expect(map(.ephemeral) == .allowed)
    }

    // MARK: Delegate

    @Test func expectedRestEndInAnActiveAppIsNotPresentedAndPlaysTheInAppAlert() {
        let presentation = RestNotificationDelegate.presentation(
            identifier: "rest-end", appState: .active, expected: true)
        #expect(presentation.options == [])
        #expect(presentation.playsInAppAlert)
    }

    @Test func expectedRestEndInAnInactiveOrBackgroundAppIsPresentedByTheSystemAndPlaysNothing() {
        for state in [RestAlertRules.AppState.inactive, .background] {
            let presentation = RestNotificationDelegate.presentation(
                identifier: "rest-end", appState: state, expected: true)
            #expect(presentation.options == [.banner, .list, .sound])
            #expect(!presentation.playsInAppAlert)
        }
    }

    @Test func aRestEndThatIsNotExpectedIsNeitherShownNorPlayedInAnyState() {
        for state in [RestAlertRules.AppState.active, .inactive, .background] {
            let presentation = RestNotificationDelegate.presentation(
                identifier: "rest-end", appState: state, expected: false)
            #expect(presentation.options == [])
            #expect(!presentation.playsInAppAlert)
        }
    }

    @Test func otherNotificationsGetTheDefaultPresentationAndNoInAppAlertInEveryState() {
        for state in [RestAlertRules.AppState.active, .inactive, .background] {
            for expected in [true, false] {
                let presentation = RestNotificationDelegate.presentation(
                    identifier: "something-else", appState: state, expected: expected)
                #expect(presentation.options == [.banner, .list, .sound])
                #expect(!presentation.playsInAppAlert)
            }
        }
    }
}
