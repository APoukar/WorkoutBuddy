import Foundation
import Testing
@testable import WorkoutBuddy

typealias ActivityContentState = WorkoutActivityAttributes.ContentState

/// A fake ActivityKit: keeps its activities, records the calls, and can hold the next call until released.
@MainActor
final class FakeActivityController: LiveActivityControlling {
    enum Call: Equatable {
        case request(UUID)
        case update(String)
        case end(String)
    }

    struct Entry {
        var info: LiveActivityInfo
        var isLive = true
    }

    var areActivitiesEnabled = true
    private(set) var entries: [Entry] = []
    private(set) var calls: [Call] = []
    /// Errors the next request calls throw (in order).
    var requestErrors: [Error] = []
    private var holdNext = false
    private var held: CheckedContinuation<Void, Never>?
    private var nextID = 1

    var isHolding: Bool { held != nil }
    var liveEntries: [LiveActivityInfo] { entries.filter(\.isLive).map(\.info) }

    func holdNextCall() { holdNext = true }

    func release() {
        held?.resume()
        held = nil
    }

    /// An activity that exists from an earlier run, or one the user dismissed / the system ended.
    func addExisting(sessionID: UUID, state: ActivityContentState, staleDate: Date? = nil, isLive: Bool = true) {
        let info = LiveActivityInfo(id: "A\(nextID)", sessionID: sessionID, state: state, staleDate: staleDate)
        nextID += 1
        entries.append(Entry(info: info, isLive: isLive))
    }

    func dismissAll() {
        for index in entries.indices { entries[index].isLive = false }
    }

    func liveActivities() -> [LiveActivityInfo] { liveEntries }

    func request(sessionID: UUID, state: ActivityContentState, staleDate: Date?) async throws {
        calls.append(.request(sessionID))
        if holdNext {
            holdNext = false
            await withCheckedContinuation { held = $0 }
        }
        if !requestErrors.isEmpty { throw requestErrors.removeFirst() }
        addExisting(sessionID: sessionID, state: state, staleDate: staleDate)
    }

    func update(id: String, state: ActivityContentState, staleDate: Date?) async {
        calls.append(.update(id))
        guard let index = entries.firstIndex(where: { $0.info.id == id }) else { return }
        entries[index].info.state = state
        entries[index].info.staleDate = staleDate
    }

    func end(id: String) async {
        calls.append(.end(id))
        guard let index = entries.firstIndex(where: { $0.info.id == id }) else { return }
        entries[index].isLive = false
    }
}

@MainActor
private final class TestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
struct LiveActivityCoordinatorTests {
    private struct RequestFailed: Error {}

    private let clock = TestClock(Date(timeIntervalSinceReferenceDate: 800_000_000))

    private func entry(_ index: Int, status: SetStatus = .pending, completedAt: Date? = nil) -> SessionSnapshot.Entry {
        SessionSnapshot.Entry(
            id: UUID(), exerciseIndex: 0, setIndex: index, exerciseID: nil,
            planned: SetValues(reps: 10, kg: 60, restSeconds: 90),
            actualReps: status == .done ? 10 : nil, actualKg: status == .done ? 60 : nil,
            status: status, completedAt: completedAt)
    }

    /// A session on its first set, or resting after it when `restLeft` is given.
    private func state(
        _ sessionID: UUID, restLeft: TimeInterval? = nil, workoutName: String? = "Push"
    ) -> SessionEffectsState {
        let start = clock.now
        var entries = [entry(0), entry(1)]
        var restEndsAt: Date?
        if let restLeft {
            entries[0] = entry(0, status: .done, completedAt: start)
            restEndsAt = start + restLeft
        }
        return .active(
            sessionID: sessionID,
            snapshot: SessionSnapshot(startedAt: start, restEndsAt: restEndsAt, exerciseCount: 1, entries: entries),
            workoutName: workoutName, exerciseNames: [:])
    }

    private func make(
        _ controller: FakeActivityController, logged: LogBox? = nil
    ) -> LiveActivityCoordinator {
        let clock = clock
        return LiveActivityCoordinator(
            controller: controller, now: { clock.now }, log: { logged?.errors.append($0) })
    }

    private final class LogBox {
        var errors: [Error] = []
    }

    private func content(_ state: SessionEffectsState) -> (state: ActivityContentState, staleDate: Date?) {
        LiveActivityContent.make(from: state, now: clock.now)!
    }

    private func apply(_ coordinator: LiveActivityCoordinator, _ state: SessionEffectsState) async {
        coordinator.reconcile(state)
        await coordinator.waitUntilIdle()
    }

    @Test func aSessionWithNoActivityRequestsOne() async {
        let controller = FakeActivityController()
        let coordinator = make(controller)
        let id = UUID()
        let session = state(id)
        await apply(coordinator, session)
        #expect(controller.calls == [.request(id)])
        #expect(controller.liveEntries.first?.state == content(session).state)
        #expect(controller.liveEntries.first?.staleDate == nil)
    }

    @Test func aRestRequestsWithTheRestEndAsStaleDate() async {
        let controller = FakeActivityController()
        let coordinator = make(controller)
        await apply(coordinator, state(UUID(), restLeft: 60))
        #expect(controller.liveEntries.first?.staleDate == clock.now + 60)
    }

    @Test func anUnchangedStateDoesNotUpdate() async {
        let controller = FakeActivityController()
        let coordinator = make(controller)
        let session = state(UUID(), restLeft: 60)
        await apply(coordinator, session)
        await apply(coordinator, session)
        #expect(controller.calls.count == 1)
    }

    @Test func aChangedStateUpdatesTheActivity() async {
        let controller = FakeActivityController()
        let coordinator = make(controller)
        let id = UUID()
        await apply(coordinator, state(id))
        await apply(coordinator, state(id, workoutName: "Pull"))
        #expect(controller.calls == [.request(id), .update("A1")])
        #expect(controller.liveEntries.first?.state.workoutName == "Pull")
    }

    @Test func aChangedStaleDateAloneUpdates() async {
        let controller = FakeActivityController()
        let id = UUID()
        let session = state(id, restLeft: 60)
        // The existing activity has the same content but another stale date.
        controller.addExisting(sessionID: id, state: content(session).state, staleDate: clock.now + 30)
        let coordinator = make(controller)
        await apply(coordinator, session)
        #expect(controller.calls == [.update("A1")])
        #expect(controller.liveEntries.first?.staleDate == clock.now + 60)
    }

    @Test func anExpiredRestUpdatesWithNoStaleDate() async {
        let controller = FakeActivityController()
        let coordinator = make(controller)
        let id = UUID()
        let session = state(id, restLeft: 60)
        await apply(coordinator, session)
        #expect(controller.liveEntries.first?.staleDate != nil)

        clock.now += 61  // The rest ran out; it isn't cleared yet.
        await apply(coordinator, session)
        #expect(controller.calls == [.request(id), .update("A1")])
        #expect(controller.liveEntries.first?.staleDate == nil)
        #expect(controller.liveEntries.first?.state.phase == .set)
    }

    @Test func noSessionEndsTheActivity() async {
        let controller = FakeActivityController()
        let coordinator = make(controller)
        await apply(coordinator, state(UUID()))
        await apply(coordinator, .none)  // Save / Discard
        #expect(controller.calls.last == .end("A1"))
        #expect(controller.liveEntries.isEmpty)
    }

    @Test func noSessionWithNoActivityDoesNothing() async {
        let controller = FakeActivityController()
        await apply(make(controller), .none)
        #expect(controller.calls.isEmpty)
    }

    @Test func aStrayOfAnotherSessionIsEndedAtLaunch() async {
        let controller = FakeActivityController()
        let stray = UUID()
        controller.addExisting(sessionID: stray, state: content(state(stray)).state)
        let id = UUID()
        await apply(make(controller), state(id))
        #expect(controller.calls == [.end("A1"), .request(id)])
        #expect(controller.liveEntries.map(\.sessionID) == [id])
    }

    @Test func aStrayIsEndedWhenThereIsNoSession() async {
        let controller = FakeActivityController()
        let stray = UUID()
        controller.addExisting(sessionID: stray, state: content(state(stray)).state)
        await apply(make(controller), .none)
        #expect(controller.calls == [.end("A1")])
    }

    @Test func endedAndDismissedActivitiesDoNotCountAsExisting() async {
        let controller = FakeActivityController()
        let id = UUID()
        let session = state(id)
        controller.addExisting(sessionID: id, state: content(session).state, isLive: false)
        await apply(make(controller), session)
        // Nothing to update or end: a new activity is requested.
        #expect(controller.calls == [.request(id)])
    }

    @Test func aDismissedActivityIsNotRequestedAgainInTheSameProcess() async {
        let controller = FakeActivityController()
        let coordinator = make(controller)
        let id = UUID()
        await apply(coordinator, state(id))
        controller.dismissAll()  // The user swiped it away.
        await apply(coordinator, state(id, restLeft: 60))
        #expect(controller.calls == [.request(id)])
        #expect(controller.liveEntries.isEmpty)
    }

    @Test func aDismissedActivityIsRequestedAgainAfterARelaunch() async {
        let controller = FakeActivityController()
        let id = UUID()
        await apply(make(controller), state(id))
        controller.dismissAll()
        await apply(make(controller), state(id))  // A new coordinator, as after a relaunch.
        #expect(controller.calls == [.request(id), .request(id)])
        #expect(controller.liveEntries.count == 1)
    }

    @Test func anExistingActivityDismissedAfterARelaunchIsNotRequestedAgain() async {
        let controller = FakeActivityController()
        let id = UUID()
        let session = state(id)
        controller.addExisting(sessionID: id, state: content(session).state)  // Left from before the kill.
        let coordinator = make(controller)
        await apply(coordinator, session)  // The launch reconcile finds it.
        controller.dismissAll()  // The user swipes it away.
        await apply(coordinator, state(id, restLeft: 60))
        #expect(controller.calls.isEmpty)
        #expect(controller.liveEntries.isEmpty)
    }

    @Test func aDuplicateActivityOfTheSameSessionIsEnded() async {
        let controller = FakeActivityController()
        let id = UUID()
        let session = state(id)
        controller.addExisting(sessionID: id, state: content(session).state)
        controller.addExisting(sessionID: id, state: content(session).state)
        await apply(make(controller), session)
        // The first is kept, and already up to date; the extra one is ended.
        #expect(controller.calls == [.end("A2")])
        #expect(controller.liveEntries.map(\.id) == ["A1"])
    }

    @Test func aFailedRequestIsRetriedAtTheNextReconcile() async {
        let controller = FakeActivityController()
        controller.requestErrors = [RequestFailed()]
        let logged = LogBox()
        let coordinator = make(controller, logged: logged)
        let id = UUID()
        await apply(coordinator, state(id))
        #expect(controller.liveEntries.isEmpty)
        await apply(coordinator, state(id))
        #expect(controller.calls == [.request(id), .request(id)])
        #expect(controller.liveEntries.count == 1)
        #expect(logged.errors.count == 1)
    }

    @Test func disabledActivitiesRequestNothing() async {
        let controller = FakeActivityController()
        controller.areActivitiesEnabled = false
        await apply(make(controller), state(UUID()))
        #expect(controller.calls.isEmpty)
    }

    @Test func aDisabledSettingStillEndsAnExistingActivity() async {
        let controller = FakeActivityController()
        let stray = UUID()
        controller.addExisting(sessionID: stray, state: content(state(stray)).state)
        controller.areActivitiesEnabled = false
        await apply(make(controller), .none)
        #expect(controller.calls == [.end("A1")])
    }

    @Test func threeQuickStatesApplyOnlyTheFirstAndTheLast() async {
        let controller = FakeActivityController()
        let coordinator = make(controller)
        let id = UUID()
        controller.holdNextCall()
        coordinator.reconcile(state(id, workoutName: "One"))
        await Task.yield()
        #expect(controller.isHolding)
        coordinator.reconcile(state(id, workoutName: "Two"))
        coordinator.reconcile(state(id, workoutName: "Three"))
        controller.release()
        await coordinator.waitUntilIdle()
        #expect(controller.calls == [.request(id), .update("A1")])
        #expect(controller.liveEntries.first?.state.workoutName == "Three")
    }

    @Test func notEnabledIsNotLoggedButOtherFailuresAre() async {
        let controller = FakeActivityController()
        controller.requestErrors = [LiveActivityError.notEnabled, RequestFailed()]
        let logged = LogBox()
        let coordinator = make(controller, logged: logged)
        let id = UUID()
        await apply(coordinator, state(id))
        #expect(logged.errors.isEmpty)
        await apply(coordinator, state(id))
        #expect(logged.errors.count == 1)
        #expect(logged.errors.first is RequestFailed)
    }
}
