import Foundation
import SwiftData
import Testing
@testable import WorkoutBuddy

/// Records what `SessionLibrary` reports, and whether the context had unsaved changes at that moment
/// (a report must come after the save, never before it or after a rollback).
@MainActor
private final class RecordingEffects: SessionEffects {
    let context: ModelContext
    private(set) var states: [SessionEffectsState] = []
    private(set) var hasChangesAtReport: [Bool] = []

    init(context: ModelContext) { self.context = context }

    func sessionChanged(_ state: SessionEffectsState) {
        states.append(state)
        hasChangesAtReport.append(context.hasChanges)
    }

    func appBecameActive(_ state: SessionEffectsState) {
        activeStates.append(state)
    }

    func requestNotificationPermissionIfNeeded() {}
    func notificationAuthorization() async -> NotificationAuthorization { .allowed }
    func restEndAlertIsCovered(restEndsAt: Date) -> Bool { false }

    /// The states reported through `appBecameActive` (kept apart from `states`, which `SessionLibrary` feeds).
    private(set) var activeStates: [SessionEffectsState] = []

    /// The snapshot of the latest report (`nil` for `.none` or no report).
    var lastSnapshot: SessionSnapshot? {
        guard case .active(_, let snapshot, _, _)? = states.last else { return nil }
        return snapshot
    }

    var lastNames: [UUID: String]? {
        guard case .active(_, _, _, let names)? = states.last else { return nil }
        return names
    }
}

@MainActor
struct SessionEffectsTests {
    private let t0 = SessionFixture.t0

    private struct Setup {
        let f: SessionFixture
        let effects: RecordingEffects
        let lib: SessionLibrary
    }

    private func makeSetup() throws -> Setup {
        let f = try SessionFixture.make()
        let effects = RecordingEffects(context: f.context)
        return Setup(f: f, effects: effects, lib: SessionLibrary(context: f.context, effects: effects))
    }

    /// A started session (one report so far) and its set IDs in order (A, B, C).
    private func started(_ s: Setup) throws -> (WorkoutSession, [UUID]) {
        let session = try s.lib.start(s.f.workout, now: t0)
        return (session, s.lib.snapshot(of: session).entries.map(\.id))
    }

    /// Expects exactly one more report than `count`, made after the save, describing the stored state.
    private func expectOneReport(
        _ s: Setup, after count: Int, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        #expect(s.effects.states.count == count + 1, sourceLocation: sourceLocation)
        #expect(s.effects.hasChangesAtReport.last == false, sourceLocation: sourceLocation)
        #expect(s.effects.states.last == (try s.lib.effectsState()), sourceLocation: sourceLocation)
    }

    // MARK: Start

    @Test func startReportsTheFirstSetAfterTheSave() throws {
        let s = try makeSetup()
        let (session, ids) = try started(s)

        try expectOneReport(s, after: 0)
        guard case .active(let sessionID, let snapshot, let workoutName, let names)? = s.effects.states.first else {
            Issue.record("Expected an active state")
            return
        }
        #expect(sessionID == session.id)
        #expect(snapshot == s.lib.snapshot(of: session))
        #expect(snapshot.screen(now: t0) == .set(0))
        #expect(snapshot.entries.map(\.id) == ids)
        #expect(workoutName == "Push Day")
        #expect(names == [s.f.bench.id: "Bench Press", s.f.squat.id: "Back Squat"])
    }

    @Test func refusedStartsReportNothingMore() throws {
        let s = try makeSetup()
        _ = try started(s)
        #expect(throws: SessionError.alreadyActive) { try s.lib.start(s.f.workout, now: t0 + 10) }
        #expect(s.effects.states.count == 1)

        let other = try makeSetup()
        try WorkoutLibrary(context: other.f.context).softDelete(other.f.workout)
        #expect(throws: SessionError.cannotStart) { try other.lib.start(other.f.workout, now: t0) }
        #expect(other.effects.states.isEmpty)
    }

    // MARK: Set actions

    @Test func doneWithRestReportsARestingState() throws {
        let s = try makeSetup()
        let (session, ids) = try started(s)
        try s.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0 + 10)

        try expectOneReport(s, after: 1)
        let snapshot = try #require(s.effects.lastSnapshot)
        #expect(snapshot.restEndsAt == t0 + 100)
        #expect(snapshot.screen(now: t0 + 20) == .rest(next: 1, remaining: 80))
        #expect(snapshot.entries[0].status == .done)
    }

    @Test func doneWithoutRestReportsTheNextSet() throws {
        let s = try makeSetup()
        let (session, ids) = try started(s)
        try s.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0 + 10)
        try s.lib.skipRest(in: session, now: t0 + 11)
        try s.lib.completeSet(in: session, setID: ids[1], reps: 8, kg: 62.5, now: t0 + 20)

        try expectOneReport(s, after: 3)
        let snapshot = try #require(s.effects.lastSnapshot)
        #expect(snapshot.restEndsAt == nil)
        #expect(snapshot.screen(now: t0 + 20) == .set(2))
    }

    @Test func skipSetReportsTheNewState() throws {
        let s = try makeSetup()
        let (session, ids) = try started(s)
        try s.lib.skipSet(in: session, setID: ids[0], now: t0 + 5)

        try expectOneReport(s, after: 1)
        #expect(s.effects.lastSnapshot?.entries[0].status == .skipped)
    }

    @Test func skipRestReportsNoRest() throws {
        let s = try makeSetup()
        let (session, ids) = try started(s)
        try s.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0 + 10)
        #expect(s.effects.lastSnapshot?.restEndsAt != nil)
        try s.lib.skipRest(in: session, now: t0 + 20)

        try expectOneReport(s, after: 2)
        #expect(s.effects.lastSnapshot?.restEndsAt == nil)
    }

    @Test func undoReportsTheSetPendingAgainWithoutRest() throws {
        let s = try makeSetup()
        let (session, ids) = try started(s)
        try s.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0 + 10)
        try s.lib.undo(in: session, setID: ids[0], now: t0 + 20)

        try expectOneReport(s, after: 2)
        let snapshot = try #require(s.effects.lastSnapshot)
        #expect(snapshot.restEndsAt == nil)
        #expect(snapshot.entries[0].status == .pending)
    }

    @Test func finishRestReportsTheClearedRest() throws {
        let s = try makeSetup()
        let (session, ids) = try started(s)
        try s.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0 + 10)
        try s.lib.finishRest(in: session, now: t0 + 100)

        try expectOneReport(s, after: 2)
        #expect(s.effects.lastSnapshot?.restEndsAt == nil)
    }

    @Test func anActionThatSavesWithoutChangingTheRestStillReports() throws {
        let s = try makeSetup()
        let (session, ids) = try started(s)
        try s.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0 + 10)
        let restEndsAt = try #require(s.effects.lastSnapshot?.restEndsAt)

        // The rest is still running, so this only stamps `lastActionAt`, but it is still a saved action.
        try s.lib.finishRest(in: session, now: t0 + 20)

        try expectOneReport(s, after: 2)
        #expect(s.effects.lastSnapshot?.restEndsAt == restEndsAt)
    }

    @Test func anActionOnAFinishedSessionReportsNothing() throws {
        let s = try makeSetup()
        let (session, ids) = try started(s)
        try s.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0 + 10)
        try s.lib.endEarly(in: session, now: t0 + 20)
        #expect(s.effects.lastSnapshot?.isFinished == true)
        let count = s.effects.states.count
        try s.lib.pause(in: session, now: t0 + 30)

        #expect(s.effects.states.count == count)
    }

    // MARK: Pause, end, back

    @Test func pauseAndResumeReportThePausedAndTheShiftedRest() throws {
        let s = try makeSetup()
        let (session, ids) = try started(s)
        try s.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0 + 10)
        try s.lib.pause(in: session, now: t0 + 30)

        try expectOneReport(s, after: 2)
        #expect(s.effects.lastSnapshot?.pausedAt == t0 + 30)
        #expect(s.effects.lastSnapshot?.isPaused == true)

        try s.lib.resume(in: session, now: t0 + 50)
        try expectOneReport(s, after: 3)
        let snapshot = try #require(s.effects.lastSnapshot)
        #expect(snapshot.isPaused == false)
        #expect(snapshot.restEndsAt == t0 + 120)
        #expect(snapshot.pausedDuration == 20)
    }

    @Test func endEarlyReportsAFinishedSession() throws {
        let s = try makeSetup()
        let (session, ids) = try started(s)
        try s.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0 + 10)
        try s.lib.endEarly(in: session, now: t0 + 20)

        try expectOneReport(s, after: 2)
        let snapshot = try #require(s.effects.lastSnapshot)
        #expect(snapshot.isFinished)
        #expect(snapshot.restEndsAt == nil)
        #expect(snapshot.status == .inProgress)
    }

    @Test func backToWorkoutReportsTheWorkoutRunningAgain() throws {
        let s = try makeSetup()
        let (session, ids) = try started(s)
        try s.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0 + 10)
        try s.lib.endEarly(in: session, now: t0 + 20)
        try s.lib.backToWorkout(in: session, now: t0 + 40)

        try expectOneReport(s, after: 3)
        let snapshot = try #require(s.effects.lastSnapshot)
        #expect(!snapshot.isFinished)
        #expect(snapshot.screen(now: t0 + 40) == .set(1))
    }

    @Test func recoveryEndReportsAFinishedSession() throws {
        let s = try makeSetup()
        let (session, ids) = try started(s)
        try s.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0 + 10)
        try s.lib.endForRecovery(session)

        try expectOneReport(s, after: 2)
        #expect(s.effects.lastSnapshot?.isFinished == true)
    }

    // MARK: Review edits

    @Test func reviewEditsEachReportTheNewState() throws {
        let s = try makeSetup()
        let (session, ids) = try started(s)
        try s.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0 + 10)
        try s.lib.skipRest(in: session, now: t0 + 11)
        try s.lib.skipSet(in: session, setID: ids[1], now: t0 + 12)
        var count = s.effects.states.count

        try s.lib.editDoneSet(in: session, setID: ids[0], reps: 12, kg: 65, now: t0 + 20)
        try expectOneReport(s, after: count)
        #expect(s.effects.lastSnapshot?.entries[0].actualReps == 12)
        #expect(s.effects.lastSnapshot?.entries[0].actualKg == 65)
        count += 1

        try s.lib.markSkippedAsDone(in: session, setID: ids[1], reps: 8, kg: 62.5, now: t0 + 21)
        try expectOneReport(s, after: count)
        #expect(s.effects.lastSnapshot?.entries[1].status == .done)
        count += 1

        try s.lib.markDoneAsSkipped(in: session, setID: ids[0], now: t0 + 22)
        try expectOneReport(s, after: count)
        #expect(s.effects.lastSnapshot?.entries[0].status == .skipped)
    }

    @Test func aReviewEditThatChangesNothingReportsNothing() throws {
        let s = try makeSetup()
        let (session, ids) = try started(s)
        try s.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0 + 10)
        let count = s.effects.states.count
        try s.lib.editDoneSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0 + 20)
        #expect(s.effects.states.count == count)
    }

    // MARK: Save and Discard

    @Test func saveReportsNone() throws {
        let s = try makeSetup()
        let (session, ids) = try started(s)
        try s.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0 + 10)
        try s.lib.endEarly(in: session, now: t0 + 20)
        let count = s.effects.states.count
        try s.lib.save(session)

        #expect(s.effects.states.count == count + 1)
        #expect(s.effects.states.last == SessionEffectsState.none)
        #expect(s.effects.hasChangesAtReport.last == false)
    }

    @Test func discardReportsNone() throws {
        let s = try makeSetup()
        let (session, _) = try started(s)
        try s.lib.discard(session)

        #expect(s.effects.states.count == 2)
        #expect(s.effects.states.last == SessionEffectsState.none)
        #expect(s.effects.hasChangesAtReport.last == false)
    }

    @Test func theLibraryNeverSendsTheCameBackMark() throws {
        // Only the app (launch, scene phase `.active`) reports `appBecameActive`; the library's actions
        // go through `sessionChanged` and so never remove delivered notifications.
        let s = try makeSetup()
        let (session, ids) = try started(s)
        try s.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0 + 10)
        try s.lib.pause(in: session, now: t0 + 20)
        try s.lib.resume(in: session, now: t0 + 30)
        try s.lib.skipRest(in: session, now: t0 + 31)
        try s.lib.skipSet(in: session, setID: ids[1], now: t0 + 32)
        try s.lib.endEarly(in: session, now: t0 + 40)
        try s.lib.save(session)

        #expect(!s.effects.states.isEmpty)
        #expect(s.effects.activeStates.isEmpty)
    }

    // MARK: Names

    @Test func namesComeFromTheReferences() throws {
        let s = try makeSetup()
        let (session, ids) = try started(s)
        #expect(s.effects.lastNames?[s.f.bench.id] == "Bench Press")

        s.f.bench.name = "Flat Bench"
        s.f.workout.name = "Press Day"
        try s.f.context.save()
        try s.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0 + 10)

        #expect(s.effects.lastNames?[s.f.bench.id] == "Flat Bench")
        guard case .active(_, _, let workoutName, _)? = s.effects.states.last else {
            Issue.record("Expected an active state")
            return
        }
        #expect(workoutName == "Press Day")
    }

    @Test func archivedExercisesAndDeletedWorkoutsStillHaveNames() throws {
        let s = try makeSetup()
        let (session, ids) = try started(s)
        try ExerciseLibrary(context: s.f.context).archive(s.f.bench)
        try WorkoutLibrary(context: s.f.context).softDelete(s.f.workout)
        try s.lib.skipSet(in: session, setID: ids[0], now: t0 + 5)

        #expect(s.effects.lastNames?[s.f.bench.id] == "Bench Press")
        guard case .active(_, _, let workoutName, _)? = s.effects.states.last else {
            Issue.record("Expected an active state")
            return
        }
        #expect(workoutName == "Push Day")
    }

    // MARK: effectsState

    @Test func effectsStateIsNoneWithoutASession() throws {
        let s = try makeSetup()
        #expect(try s.lib.effectsState() == SessionEffectsState.none)
    }

    @Test func effectsStateIsNoneForASavedSession() throws {
        let s = try makeSetup()
        let (session, ids) = try started(s)
        try s.lib.completeSet(in: session, setID: ids[0], reps: 10, kg: 60, now: t0 + 10)
        try s.lib.endEarly(in: session, now: t0 + 20)
        try s.lib.save(session)
        #expect(try s.lib.effectsState() == SessionEffectsState.none)
    }

    @Test func exerciseNamesAreLookedUpThroughTheReferences() throws {
        let s = try makeSetup()
        let (session, _) = try started(s)
        #expect(s.lib.exerciseNames(of: session) == [s.f.bench.id: "Bench Press", s.f.squat.id: "Back Squat"])
        s.f.squat.name = "Front Squat"
        #expect(s.lib.exerciseNames(of: session)[s.f.squat.id] == "Front Squat")
    }

    @Test func theDefaultLibraryHasNoEffectsInTests() throws {
        #expect(SessionEffectsProvider.current is NoSessionEffects)
        let f = try SessionFixture.make()
        #expect(SessionLibrary(context: f.context).effects is NoSessionEffects)
    }

    // MARK: Provider gate

    @Test func providerGateIsInertForTestsUITestingAndPreviews() throws {
        let uiTesting = UITestingLaunch.parse([UITestingContract.Argument.uiTesting, UITestingContract.Argument.yes])
        #expect(uiTesting != nil)

        #expect(!SessionEffectsProvider.isInert(environment: [:], uiTesting: nil))
        #expect(!SessionEffectsProvider.isInert(environment: ["XCODE_RUNNING_FOR_PREVIEWS": "0"], uiTesting: nil))
        #expect(SessionEffectsProvider.isInert(environment: ["XCTestConfigurationFilePath": "/tmp/x"], uiTesting: nil))
        #expect(SessionEffectsProvider.isInert(environment: ["XCTestBundlePath": "/tmp/x"], uiTesting: nil))
        #expect(SessionEffectsProvider.isInert(environment: [:], uiTesting: uiTesting))
        #expect(SessionEffectsProvider.isInert(environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"], uiTesting: nil))
    }

    @Test func noSessionEffectsDoesNothingAndAllowsNotifications() async {
        let effects = NoSessionEffects()
        effects.sessionChanged(.none)
        effects.appBecameActive(.none)
        effects.requestNotificationPermissionIfNeeded()
        #expect(await effects.notificationAuthorization() == .allowed)
        #expect(!effects.restEndAlertIsCovered(restEndsAt: .now))
    }
}
