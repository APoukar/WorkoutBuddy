import Foundation
import Testing
@testable import WorkoutBuddy

/// Records every call, and can hold the next call until released, to test what happens while a system
/// call is in flight.
@MainActor
private final class FakeScheduler: NotificationScheduling {
    enum Call: Equatable {
        /// The fire date of the scheduled request (the full request is in `requests`).
        case schedule(Date)
        case cancel
        case removeDelivered
    }

    private(set) var calls: [Call] = []
    private(set) var requests: [RestNotificationRequest] = []
    var scheduleErrors: [Error] = []
    private var holdNext = false
    private var held: CheckedContinuation<Void, Never>?

    var isHolding: Bool { held != nil }

    /// The next call suspends until `release()`.
    func holdNextCall() { holdNext = true }

    func release() {
        held?.resume()
        held = nil
    }

    private func holdIfAsked() async {
        guard holdNext else { return }
        holdNext = false
        await withCheckedContinuation { held = $0 }
    }

    func schedule(_ request: RestNotificationRequest) async throws {
        calls.append(.schedule(request.fireDate))
        requests.append(request)
        await holdIfAsked()
        if !scheduleErrors.isEmpty { throw scheduleErrors.removeFirst() }
    }

    func cancel() async {
        calls.append(.cancel)
        await holdIfAsked()
    }

    func removeDelivered() async {
        calls.append(.removeDelivered)
        await holdIfAsked()
    }

    func authorization() async -> NotificationAuthorization { .allowed }
    func requestAuthorization() async throws {}
}

@MainActor
private final class LogRecorder {
    var errors: [Error] = []
}

@MainActor
private final class TestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
struct RestNotificationCoordinatorTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let settings = AppSettings.Values(
        reps: 10, kg: 20, restSeconds: 90, weightStep: .twoAndHalf, soundEnabled: true, hapticsEnabled: true)
    private let exerciseID = UUID()

    private struct Failure: Error {}

    private struct Setup {
        let scheduler: FakeScheduler
        let clock: TestClock
        let logged: LogRecorder
        let coordinator: RestNotificationCoordinator
    }

    private func makeSetup(now: Date? = nil) -> Setup {
        let clock = TestClock(now ?? t0 + 10)
        let scheduler = FakeScheduler()
        let logged = LogRecorder()
        return Setup(
            scheduler: scheduler, clock: clock, logged: logged,
            coordinator: RestNotificationCoordinator(
                scheduler: scheduler, now: { clock.now }, log: { logged.errors.append($0) }))
    }

    /// A session resting until `restEndsAt` (nil: on a set, so the plan is `.cancel`).
    private func state(restEndsAt: Date?) -> SessionEffectsState {
        let entries = [
            SessionSnapshot.Entry(
                id: UUID(), exerciseIndex: 0, setIndex: 0, exerciseID: exerciseID,
                planned: SetValues(reps: 10, kg: 60, restSeconds: 90), actualReps: 10, actualKg: 60,
                status: .done, completedAt: t0),
            SessionSnapshot.Entry(
                id: UUID(), exerciseIndex: 0, setIndex: 1, exerciseID: exerciseID,
                planned: SetValues(reps: 8, kg: 62.5, restSeconds: 90), actualReps: nil, actualKg: nil,
                status: .pending, completedAt: nil),
        ]
        return .active(
            sessionID: UUID(),
            snapshot: SessionSnapshot(startedAt: t0, restEndsAt: restEndsAt, exerciseCount: 1, entries: entries),
            workoutName: "Push Day", exerciseNames: [exerciseID: "Bench Press"])
    }

    /// Lets the coordinator's task run until the fake holds a call.
    private func waitUntilHolding(_ scheduler: FakeScheduler) async {
        for _ in 0..<1000 where !scheduler.isHolding { await Task.yield() }
    }

    // MARK: Applying plans

    @Test func aRestSchedulesTheNotification() async {
        let s = makeSetup()
        s.coordinator.reconcile(state(restEndsAt: t0 + 100), settings: settings)
        await s.coordinator.waitUntilIdle()
        #expect(s.scheduler.calls == [.schedule(t0 + 100)])
        #expect(s.logged.errors.isEmpty)
        // The request is the plan's: the title and the sound come through.
        #expect(s.scheduler.requests.first?.title == "Rest Over")
        #expect(s.scheduler.requests.first?.sound == .chime)
    }

    @Test func scheduleThenCancelEndsCancelled() async {
        let s = makeSetup()
        s.coordinator.reconcile(state(restEndsAt: t0 + 100), settings: settings)
        await s.coordinator.waitUntilIdle()
        s.clock.now = t0 + 20
        s.coordinator.reconcile(state(restEndsAt: nil), settings: settings)
        await s.coordinator.waitUntilIdle()
        #expect(s.scheduler.calls == [.schedule(t0 + 100), .cancel])
    }

    @Test func aRescheduleReplacesTheNotification() async {
        let s = makeSetup()
        s.coordinator.reconcile(state(restEndsAt: t0 + 100), settings: settings)
        await s.coordinator.waitUntilIdle()
        s.coordinator.reconcile(state(restEndsAt: t0 + 130), settings: settings)
        await s.coordinator.waitUntilIdle()
        #expect(s.scheduler.calls == [
            .schedule(t0 + 100), .schedule(t0 + 130),
        ])
    }

    @Test func statesThatArriveDuringACallApplyOnlyTheFirstAndTheLast() async {
        let s = makeSetup()
        s.scheduler.holdNextCall()
        s.coordinator.reconcile(state(restEndsAt: t0 + 100), settings: settings)  // first
        await waitUntilHolding(s.scheduler)
        #expect(s.scheduler.isHolding)

        s.coordinator.reconcile(state(restEndsAt: t0 + 110), settings: settings)  // skipped
        s.coordinator.reconcile(state(restEndsAt: t0 + 120), settings: settings)  // skipped
        s.coordinator.reconcile(state(restEndsAt: t0 + 130), settings: settings)  // last
        #expect(s.scheduler.calls == [.schedule(t0 + 100)])

        s.scheduler.release()
        await s.coordinator.waitUntilIdle()
        #expect(s.scheduler.calls == [
            .schedule(t0 + 100), .schedule(t0 + 130),
        ])
    }

    @Test func applicationIsSerial() async {
        let s = makeSetup()
        s.scheduler.holdNextCall()
        s.coordinator.reconcile(state(restEndsAt: t0 + 100), settings: settings)
        await waitUntilHolding(s.scheduler)
        s.clock.now = t0 + 20
        s.coordinator.reconcile(state(restEndsAt: nil), settings: settings)
        for _ in 0..<50 { await Task.yield() }
        // The cancel waits for the schedule in flight.
        #expect(s.scheduler.calls == [.schedule(t0 + 100)])
        s.scheduler.release()
        await s.coordinator.waitUntilIdle()
        #expect(s.scheduler.calls == [.schedule(t0 + 100), .cancel])
    }

    // MARK: Failures

    @Test func aFailureIsLoggedAndTheNextStateStillApplies() async {
        let s = makeSetup()
        s.scheduler.scheduleErrors = [Failure()]
        s.coordinator.reconcile(state(restEndsAt: t0 + 100), settings: settings)
        await s.coordinator.waitUntilIdle()
        #expect(s.logged.errors.count == 1)
        #expect(s.logged.errors.first is Failure)

        s.coordinator.reconcile(state(restEndsAt: t0 + 130), settings: settings)
        await s.coordinator.waitUntilIdle()
        #expect(s.scheduler.calls.last == .schedule(t0 + 130))
        #expect(s.logged.errors.count == 1)
    }

    @Test func notAllowedIsNotLoggedAndTheNextStateStillApplies() async {
        let s = makeSetup()
        s.scheduler.scheduleErrors = [NotificationSchedulingError.notAllowed]
        s.coordinator.reconcile(state(restEndsAt: t0 + 100), settings: settings)
        await s.coordinator.waitUntilIdle()
        #expect(s.logged.errors.isEmpty)

        s.clock.now = t0 + 20
        s.coordinator.reconcile(state(restEndsAt: nil), settings: settings)
        await s.coordinator.waitUntilIdle()
        #expect(s.scheduler.calls.last == .cancel)
        #expect(s.logged.errors.isEmpty)
    }

    // MARK: Delivered notifications

    @Test func deliveredNotificationsAreRemovedOnlyOnTheActiveReconcile() async {
        let s = makeSetup()
        s.coordinator.reconcile(state(restEndsAt: t0 + 100), settings: settings)
        await s.coordinator.waitUntilIdle()
        s.coordinator.reconcile(state(restEndsAt: nil), settings: settings)
        await s.coordinator.waitUntilIdle()
        #expect(!s.scheduler.calls.contains(.removeDelivered))

        s.coordinator.reconcile(state(restEndsAt: nil), settings: settings, appBecameActive: true)
        await s.coordinator.waitUntilIdle()
        #expect(s.scheduler.calls.filter { $0 == .removeDelivered }.count == 1)

        s.coordinator.reconcile(state(restEndsAt: nil), settings: settings)
        await s.coordinator.waitUntilIdle()
        #expect(s.scheduler.calls.filter { $0 == .removeDelivered }.count == 1)
    }

    @Test func theActiveMarkSurvivesANewerStateReplacingIt() async {
        let s = makeSetup()
        s.scheduler.holdNextCall()
        s.coordinator.reconcile(state(restEndsAt: t0 + 100), settings: settings)
        await waitUntilHolding(s.scheduler)

        s.coordinator.reconcile(state(restEndsAt: t0 + 110), settings: settings, appBecameActive: true)
        s.coordinator.reconcile(state(restEndsAt: t0 + 120), settings: settings)  // replaces the marked one
        s.scheduler.release()
        await s.coordinator.waitUntilIdle()
        #expect(s.scheduler.calls == [
            .schedule(t0 + 100), .removeDelivered, .schedule(t0 + 120),
        ])
    }

    // MARK: The 1 s cancel guard

    @Test func aCancelJustBeforeTheFireDateStillCancels() async {
        let s = makeSetup()
        s.coordinator.reconcile(state(restEndsAt: t0 + 100), settings: settings)
        await s.coordinator.waitUntilIdle()
        s.clock.now = t0 + 99.5
        s.coordinator.reconcile(state(restEndsAt: nil), settings: settings)
        await s.coordinator.waitUntilIdle()
        #expect(s.scheduler.calls == [.schedule(t0 + 100), .cancel])
    }

    @Test func aCancelExactlyAtTheFireDateIsSkipped() async {
        let s = makeSetup()
        s.coordinator.reconcile(state(restEndsAt: t0 + 100), settings: settings)
        await s.coordinator.waitUntilIdle()
        s.clock.now = t0 + 100
        s.coordinator.reconcile(state(restEndsAt: nil), settings: settings)
        await s.coordinator.waitUntilIdle()
        #expect(s.scheduler.calls == [.schedule(t0 + 100)])
    }

    @Test func aCancelExactlyASecondAfterTheFireDateIsSkipped() async {
        let s = makeSetup()
        s.coordinator.reconcile(state(restEndsAt: t0 + 100), settings: settings)
        await s.coordinator.waitUntilIdle()
        s.clock.now = t0 + 101
        s.coordinator.reconcile(state(restEndsAt: nil), settings: settings)
        await s.coordinator.waitUntilIdle()
        #expect(s.scheduler.calls == [.schedule(t0 + 100)])
    }

    @Test func aCancelMoreThanASecondAfterTheFireDateApplies() async {
        let s = makeSetup()
        s.coordinator.reconcile(state(restEndsAt: t0 + 100), settings: settings)
        await s.coordinator.waitUntilIdle()
        s.clock.now = t0 + 101.5
        s.coordinator.reconcile(state(restEndsAt: nil), settings: settings)
        await s.coordinator.waitUntilIdle()
        #expect(s.scheduler.calls == [.schedule(t0 + 100), .cancel])
    }

    @Test func aCancelJustAfterTheFireDateIsSkipped() async {
        let s = makeSetup()
        s.coordinator.reconcile(state(restEndsAt: t0 + 100), settings: settings)
        await s.coordinator.waitUntilIdle()
        s.clock.now = t0 + 100.5
        s.coordinator.reconcile(state(restEndsAt: nil), settings: settings)
        await s.coordinator.waitUntilIdle()
        #expect(s.scheduler.calls == [.schedule(t0 + 100)])
    }

    @Test func aCancelMoreThanASecondAwayApplies() async {
        let s = makeSetup()
        s.coordinator.reconcile(state(restEndsAt: t0 + 100), settings: settings)
        await s.coordinator.waitUntilIdle()
        s.clock.now = t0 + 98.5
        s.coordinator.reconcile(state(restEndsAt: nil), settings: settings)
        await s.coordinator.waitUntilIdle()
        #expect(s.scheduler.calls == [.schedule(t0 + 100), .cancel])
    }

    @Test func aCancelWithNothingScheduledByThisCoordinatorApplies() async {
        // After a relaunch the coordinator doesn't know what is pending, so it cancels.
        let s = makeSetup(now: t0 + 100)
        s.coordinator.reconcile(state(restEndsAt: nil), settings: settings)
        await s.coordinator.waitUntilIdle()
        #expect(s.scheduler.calls == [.cancel])
    }

    @Test func theGuardOnlyAppliesToTheNotificationThatWasScheduled() async {
        let s = makeSetup()
        s.coordinator.reconcile(state(restEndsAt: t0 + 100), settings: settings)
        await s.coordinator.waitUntilIdle()
        s.clock.now = t0 + 100.5
        s.coordinator.reconcile(state(restEndsAt: nil), settings: settings)  // skipped: just fired
        await s.coordinator.waitUntilIdle()
        s.coordinator.reconcile(state(restEndsAt: nil), settings: settings)  // nothing known to be pending
        await s.coordinator.waitUntilIdle()
        #expect(s.scheduler.calls == [.schedule(t0 + 100), .cancel])
    }
}
