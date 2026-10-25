import Foundation
import Testing
@testable import WorkoutBuddy

struct SessionPresentationRulesTests {
    private let id = UUID()

    @Test func coverShowsTheFirstSessionOnceTheCheckIsDone() {
        #expect(SessionPresentationRules.coverSessionID(launchCheckDone: true, recoveryPending: false, firstSessionID: id) == id)
    }

    @Test func coverWaitsForTheLaunchCheck() {
        #expect(SessionPresentationRules.coverSessionID(launchCheckDone: false, recoveryPending: false, firstSessionID: id) == nil)
    }

    @Test func coverWaitsForTheRecoveryAnswer() {
        #expect(SessionPresentationRules.coverSessionID(launchCheckDone: true, recoveryPending: true, firstSessionID: id) == nil)
        #expect(SessionPresentationRules.coverSessionID(launchCheckDone: false, recoveryPending: true, firstSessionID: id) == nil)
    }

    @Test func noSessionMeansNoCover() {
        #expect(SessionPresentationRules.coverSessionID(launchCheckDone: true, recoveryPending: false, firstSessionID: nil) == nil)
        #expect(SessionPresentationRules.coverSessionID(launchCheckDone: false, recoveryPending: false, firstSessionID: nil) == nil)
    }

    @Test func askResumeBecomesAPendingRecovery() {
        let withSet = SessionPresentationRules.pendingRecovery(for: .askResume(canSave: true), sessionID: id, workoutName: "Push Day")
        #expect(withSet == PendingRecovery(sessionID: id, workoutName: "Push Day", canSave: true))
        let withoutSet = SessionPresentationRules.pendingRecovery(for: .askResume(canSave: false), sessionID: id, workoutName: nil)
        #expect(withoutSet == PendingRecovery(sessionID: id, workoutName: nil, canSave: false))
    }

    @Test func otherDecisionsAskNothing() {
        #expect(SessionPresentationRules.pendingRecovery(for: .showSummary, sessionID: id, workoutName: "Push Day") == nil)
        #expect(SessionPresentationRules.pendingRecovery(for: .nothingToRecover, sessionID: id, workoutName: "Push Day") == nil)
    }

    @Test func recoveryMessageNamesTheWorkoutOrFallsBack() {
        #expect(PendingRecovery(sessionID: id, workoutName: "Push Day", canSave: true).message
            == "\u{201C}Push Day\u{201D} was still in progress.")
        #expect(PendingRecovery(sessionID: id, workoutName: nil, canSave: true).message
            == "Your workout was still in progress.")
    }

    @Test func recoveryAlertShowsWhilePendingAndNoErrorIsUp() {
        let pending = PendingRecovery(sessionID: id, workoutName: "Push Day", canSave: true)
        #expect(SessionPresentationRules.showsRecoveryAlert(recovery: pending, hasError: false))
        #expect(!SessionPresentationRules.showsRecoveryAlert(recovery: pending, hasError: true))
        #expect(!SessionPresentationRules.showsRecoveryAlert(recovery: nil, hasError: false))
        #expect(!SessionPresentationRules.showsRecoveryAlert(recovery: nil, hasError: true))
    }
}
