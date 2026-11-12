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
}
