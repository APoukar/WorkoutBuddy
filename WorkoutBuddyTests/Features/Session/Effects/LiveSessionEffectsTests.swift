import Foundation
import Testing
@testable import WorkoutBuddy

/// Records the calls the live effects make through a fake scheduler (never the real notification center).
@MainActor
private final class RecordingScheduler: NotificationScheduling {
    enum Call: Equatable {
        case schedule, cancel, removeDelivered
    }

    private(set) var calls: [Call] = []
    var scheduleError: Error?
    var scheduleResult: NotificationScheduleResult = .added

    func schedule(_ request: RestNotificationRequest) async throws -> NotificationScheduleResult {
        calls.append(.schedule)
        if let scheduleError { throw scheduleError }
        return scheduleResult
    }
    func cancel() async { calls.append(.cancel) }
    func removeDelivered() async { calls.append(.removeDelivered) }
    func authorization() async -> NotificationAuthorization { .allowed }
    func requestAuthorization() async throws {}
}

@MainActor
struct LiveSessionEffectsTests {
    private let settings = AppSettings.Values(
        reps: 10, kg: 20, restSeconds: 90, weightStep: .twoAndHalf, soundEnabled: true, hapticsEnabled: true)

    /// A session resting for another minute (or `restLeft` seconds), so the plan is a schedule.
    private func restingState(restLeft: TimeInterval = 60) -> SessionEffectsState {
        let start = Date.now
        let entries = [
            SessionSnapshot.Entry(
                id: UUID(), exerciseIndex: 0, setIndex: 0, exerciseID: nil,
                planned: SetValues(reps: 10, kg: 60, restSeconds: 90), actualReps: 10, actualKg: 60,
                status: .done, completedAt: start),
            SessionSnapshot.Entry(
                id: UUID(), exerciseIndex: 0, setIndex: 1, exerciseID: nil,
                planned: SetValues(reps: 8, kg: 62.5, restSeconds: 90), actualReps: nil, actualKg: nil,
                status: .pending, completedAt: nil),
        ]
        return .active(
            sessionID: UUID(),
            snapshot: SessionSnapshot(
                startedAt: start, restEndsAt: start + restLeft, exerciseCount: 1, entries: entries),
            workoutName: nil, exerciseNames: [:])
    }

    @Test func sessionChangedReconcilesWithoutRemovingDelivered() async {
        let scheduler = RecordingScheduler()
        let effects = LiveSessionEffects(scheduler: scheduler, settings: { settings })
        effects.sessionChanged(restingState())
        await effects.waitUntilIdle()
        #expect(scheduler.calls == [.schedule])
    }

    @Test func appBecameActiveAlsoRemovesDelivered() async {
        let scheduler = RecordingScheduler()
        let effects = LiveSessionEffects(scheduler: scheduler, settings: { settings })
        effects.appBecameActive(restingState())
        await effects.waitUntilIdle()
        #expect(scheduler.calls == [.schedule, .removeDelivered])
    }

    @Test func appBecameActiveWithoutASessionCancels() async {
        let scheduler = RecordingScheduler()
        let effects = LiveSessionEffects(scheduler: scheduler, settings: { settings })
        effects.appBecameActive(.none)
        await effects.waitUntilIdle()
        #expect(scheduler.calls == [.cancel, .removeDelivered])
    }

    @Test func theRestEndIsCoveredAfterASuccessfulSchedule() async {
        let scheduler = RecordingScheduler()
        let effects = LiveSessionEffects(scheduler: scheduler, settings: { settings })
        let state = restingState()
        guard case .active(_, let snapshot, _, _) = state, let restEndsAt = snapshot.restEndsAt else {
            Issue.record("Expected a resting state")
            return
        }
        #expect(!effects.restEndAlertIsCovered(restEndsAt: restEndsAt))

        effects.sessionChanged(state)
        await effects.waitUntilIdle()
        #expect(effects.restEndAlertIsCovered(restEndsAt: restEndsAt))
        #expect(!effects.restEndAlertIsCovered(restEndsAt: restEndsAt + 30))
    }

    @Test func theRestEndIsNotCoveredWhenSchedulingIsNotAllowed() async {
        let scheduler = RecordingScheduler()
        scheduler.scheduleError = NotificationSchedulingError.notAllowed
        let effects = LiveSessionEffects(scheduler: scheduler, settings: { settings })
        let state = restingState()
        guard case .active(_, let snapshot, _, _) = state, let restEndsAt = snapshot.restEndsAt else {
            Issue.record("Expected a resting state")
            return
        }
        effects.sessionChanged(state)
        await effects.waitUntilIdle()
        #expect(scheduler.calls == [.schedule])
        #expect(!effects.restEndAlertIsCovered(restEndsAt: restEndsAt))
    }

    @Test func aRestEndIsExpectedWhileACoverExistsAndNotAfterAPause() async {
        let scheduler = RecordingScheduler()
        let effects = LiveSessionEffects(scheduler: scheduler, settings: { settings })
        #expect(!effects.restEndIsExpected)

        effects.sessionChanged(restingState())
        await effects.waitUntilIdle()
        #expect(effects.restEndIsExpected)

        effects.sessionChanged(.none)  // Discard, Pause, Skip Rest...: decided before the fire date.
        #expect(!effects.restEndIsExpected)
        await effects.waitUntilIdle()
        #expect(!effects.restEndIsExpected)
    }

    @Test func aResumeWithLessThanASecondLeftIsNotCoveredSoTheAppAlertsItself() async {
        // The real scheduler returns `.tooLate` for under a second left (see `triggerInterval`).
        let scheduler = RecordingScheduler()
        scheduler.scheduleResult = .tooLate
        let effects = LiveSessionEffects(scheduler: scheduler, settings: { settings })
        let state = restingState(restLeft: 0.55)
        guard case .active(_, let snapshot, _, _) = state, let restEndsAt = snapshot.restEndsAt else {
            Issue.record("Expected a resting state")
            return
        }
        effects.sessionChanged(state)
        await effects.waitUntilIdle()
        #expect(scheduler.calls == [.schedule])
        #expect(!effects.restEndAlertIsCovered(restEndsAt: restEndsAt))  // `autoAdvance` plays.
        #expect(!effects.restEndIsExpected)
    }
}
