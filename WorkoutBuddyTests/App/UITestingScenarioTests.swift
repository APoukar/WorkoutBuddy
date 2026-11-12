import Foundation
import SwiftData
import Testing
@testable import WorkoutBuddy

@MainActor
struct UITestingScenarioTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    /// A fresh in-memory store with the exercise seed and the scenario.
    private func make(_ scenario: UITestingLaunch.Scenario) throws -> TestContainer {
        let tc = try TestContainer()
        try ExerciseSeed.seedIfNeeded(in: tc.context)
        try UITestingScenario.seed(scenario, in: tc.container, now: now)
        return tc
    }

    private func workouts(_ tc: TestContainer) throws -> [Workout] {
        try tc.context.fetch(FetchDescriptor<Workout>())
    }

    private func sessions(_ tc: TestContainer) throws -> [WorkoutSession] {
        try tc.context.fetch(FetchDescriptor<WorkoutSession>())
    }

    private func name(of exerciseID: UUID?, in tc: TestContainer) throws -> String? {
        let all = try tc.context.fetch(FetchDescriptor<Exercise>())
        return all.first { $0.id == exerciseID }?.name
    }

    // MARK: Templates

    @Test func emptySeedsNothing() throws {
        let tc = try make(.empty)
        #expect(try workouts(tc).isEmpty)
        #expect(try sessions(tc).isEmpty)
        #expect(try tc.context.fetchCount(FetchDescriptor<Exercise>()) > 0)
    }

    @Test func templatesHasTheTwoWorkoutsAndNoSession() throws {
        let tc = try make(.templates)
        let found = try workouts(tc)
        #expect(Set(found.map(\.name)) == ["Short Rests", "Long Rests"])
        #expect(found.allSatisfy { !$0.isSoftDeleted })
        #expect(try sessions(tc).isEmpty)
    }

    @Test func everyScenarioButEmptyHasBothTemplates() throws {
        for scenario in [UITestingLaunch.Scenario.templates, .inProgress, .nothingDone, .onSummary] {
            let tc = try make(scenario)
            #expect(Set(try workouts(tc).map(\.name)) == ["Short Rests", "Long Rests"], "\(scenario)")
        }
    }

    @Test func templateSetsAndRests() throws {
        let tc = try make(.templates)
        let library = WorkoutLibrary(context: tc.context)
        for (workoutName, rests) in [("Short Rests", [10, 0, 10]), ("Long Rests", [600, 600, 600])] {
            let workout = try #require(try workouts(tc).first { $0.name == workoutName })
            let draft = library.draft(for: workout)
            #expect(draft.exercises.count == 2)
            #expect(try name(of: draft.exercises[0].exerciseID, in: tc) == "Bench Press")
            #expect(try name(of: draft.exercises[1].exerciseID, in: tc) == "Overhead Press")
            #expect(
                draft.exercises[0].sets.map(\.values) == [
                    SetValues(reps: 10, kg: 60, restSeconds: rests[0]),
                    SetValues(reps: 8, kg: 62.5, restSeconds: rests[1]),
                ], "\(workoutName)")
            #expect(draft.exercises[1].sets.map(\.values) == [SetValues(reps: 8, kg: 40, restSeconds: rests[2])], "\(workoutName)")
        }
    }

    // MARK: Sessions

    private func onlySession(_ tc: TestContainer) throws -> (WorkoutSession, SessionSnapshot) {
        let all = try sessions(tc)
        #expect(all.count == 1)
        let session = try #require(all.first)
        return (session, SessionLibrary(context: tc.context).snapshot(of: session))
    }

    @Test func inProgressSession() throws {
        let tc = try make(.inProgress)
        let (session, snapshot) = try onlySession(tc)
        #expect(session.workout?.name == "Long Rests")
        #expect(session.status == .inProgress)
        #expect(snapshot.entries.map(\.status) == [.done, .skipped, .pending])
        #expect(snapshot.currentSetIndex == 2)
        #expect(try name(of: snapshot.entries[2].exerciseID, in: tc) == "Overhead Press")
        #expect(snapshot.entries[0].actualReps == 10)
        #expect(snapshot.entries[0].actualKg == 60)
        #expect(snapshot.entries[1].actualReps == nil)
        #expect(snapshot.entries.map(\.planned.restSeconds) == [600, 600, 600])
        #expect(!snapshot.isFinished)
        #expect(!snapshot.isPaused)
        #expect(snapshot.restEndsAt == nil)
        #expect(snapshot.screen(now: now) == .set(2))
        #expect(snapshot.startedAt == now.addingTimeInterval(-300))
        #expect(snapshot.lastActionAt == now.addingTimeInterval(-230))
        let stats = SessionStats(snapshot, now: now)
        #expect(stats.doneCount == 1)
        #expect(stats.skippedCount == 1)
        #expect(LaunchRecovery.decide(snapshot) == .askResume(canSave: true))
    }

    @Test func nothingDoneSession() throws {
        let tc = try make(.nothingDone)
        let (session, snapshot) = try onlySession(tc)
        #expect(session.workout?.name == "Long Rests")
        #expect(snapshot.entries.map(\.status) == [.skipped, .pending, .pending])
        #expect(snapshot.currentSetIndex == 1)
        #expect(!snapshot.hasDoneSet)
        #expect(!snapshot.isFinished)
        #expect(snapshot.restEndsAt == nil)
        #expect(snapshot.screen(now: now) == .set(1))
        #expect(LaunchRecovery.decide(snapshot) == .askResume(canSave: false))
    }

    @Test func onSummarySession() throws {
        let tc = try make(.onSummary)
        let (session, snapshot) = try onlySession(tc)
        #expect(session.workout?.name == "Long Rests")
        #expect(session.status == .inProgress)
        #expect(snapshot.entries.map(\.status) == [.done, .done, .done])
        #expect(snapshot.entries.map(\.actualReps) == [10, 8, 8])
        #expect(snapshot.entries.map(\.actualKg) == [60, 62.5, 40])
        #expect(snapshot.currentSetIndex == nil)
        #expect(snapshot.isFinished)
        #expect(snapshot.restEndsAt == nil)
        #expect(snapshot.screen(now: now) == .summary)
        #expect(LaunchRecovery.decide(snapshot) == .showSummary)
        #expect(snapshot.startedAt == now.addingTimeInterval(-600))
        #expect(snapshot.endedAt == now.addingTimeInterval(-300))
        let stats = SessionStats(snapshot, now: now)
        #expect(stats.volume == 1420)
        #expect(stats.doneCount == 3)
        #expect(stats.notPerformedCount == 0)
    }

    // MARK: Keep data

    @Test func keepDataLaunchSeedsNothing() throws {
        // WorkoutBuddyApp seeds a scenario only when `seedsScenario` is true, which keep data turns off.
        let keep = UITestingLaunch(scenario: .inProgress, store: .disk, keepData: true)
        let fresh = UITestingLaunch(scenario: .inProgress, store: .disk, keepData: false)
        #expect(!keep.seedsScenario)
        #expect(fresh.seedsScenario)
    }
}
