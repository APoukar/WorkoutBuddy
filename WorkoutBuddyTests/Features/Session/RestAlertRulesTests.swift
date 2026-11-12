import Foundation
import Testing
@testable import WorkoutBuddy

struct RestAlertRulesTests {
    private let endsAt = Date(timeIntervalSince1970: 1_000_000)

    @Test func playsWhenNoticedAtTheEnd() {
        #expect(RestAlertRules.shouldPlayAlert(restEndsAt: endsAt, noticedAt: endsAt))
        #expect(RestAlertRules.shouldPlayAlert(restEndsAt: endsAt, noticedAt: endsAt.addingTimeInterval(0.4)))
    }

    @Test func playsUpToTheEndOfTheWindow() {
        #expect(RestAlertRules.shouldPlayAlert(restEndsAt: endsAt, noticedAt: endsAt.addingTimeInterval(2)))
    }

    @Test func staysSilentWhenNoticedLate() {
        #expect(!RestAlertRules.shouldPlayAlert(restEndsAt: endsAt, noticedAt: endsAt.addingTimeInterval(2.01)))
        #expect(!RestAlertRules.shouldPlayAlert(restEndsAt: endsAt, noticedAt: endsAt.addingTimeInterval(600)))
    }

    @Test func staysSilentWhenNoticedBeforeTheEnd() {
        #expect(!RestAlertRules.shouldPlayAlert(restEndsAt: endsAt, noticedAt: endsAt.addingTimeInterval(-0.5)))
    }

    // MARK: What to do at the rest end, by app state and coverage

    @Test(arguments: [true, false])
    func backgroundLeavesTheRestStored(covered: Bool) {
        #expect(
            RestAlertRules.action(appState: .background, restEndsAt: endsAt, noticedAt: endsAt, covered: covered)
                == .leaveStored)
        #expect(
            RestAlertRules.action(
                appState: .background, restEndsAt: endsAt, noticedAt: endsAt.addingTimeInterval(600), covered: covered)
                == .leaveStored)
    }

    @Test(arguments: [RestAlertRules.AppState.active, .inactive])
    func aCoveredRestIsClearedSilentlyInTheForeground(appState: RestAlertRules.AppState) {
        // The notification (or its delegate) alerts, so the app never plays one, however promptly it noticed.
        #expect(
            RestAlertRules.action(appState: appState, restEndsAt: endsAt, noticedAt: endsAt, covered: true)
                == .clearSilently)
        #expect(
            RestAlertRules.action(
                appState: appState, restEndsAt: endsAt, noticedAt: endsAt.addingTimeInterval(0.5), covered: true)
                == .clearSilently)
        #expect(
            RestAlertRules.action(
                appState: appState, restEndsAt: endsAt, noticedAt: endsAt.addingTimeInterval(30), covered: true)
                == .clearSilently)
    }

    @Test(arguments: [RestAlertRules.AppState.active, .inactive])
    func anUncoveredRestPlaysTheAlertWhenNoticedOnTime(appState: RestAlertRules.AppState) {
        #expect(
            RestAlertRules.action(appState: appState, restEndsAt: endsAt, noticedAt: endsAt, covered: false)
                == .clearAndPlayAlert)
        #expect(
            RestAlertRules.action(
                appState: appState, restEndsAt: endsAt, noticedAt: endsAt.addingTimeInterval(2), covered: false)
                == .clearAndPlayAlert)
    }

    @Test(arguments: [RestAlertRules.AppState.active, .inactive])
    func anUncoveredRestClearsSilentlyWhenNoticedLate(appState: RestAlertRules.AppState) {
        let late = endsAt.addingTimeInterval(30)
        #expect(
            RestAlertRules.action(appState: appState, restEndsAt: endsAt, noticedAt: late, covered: false)
                == .clearSilently)
    }
}
