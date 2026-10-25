import Foundation
import Testing
@testable import WorkoutBuddy

struct LaunchRecoveryTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func entry(_ status: SetStatus, at index: Int, completedAt: Date? = nil) -> SessionSnapshot.Entry {
        SessionSnapshot.Entry(
            id: UUID(), exerciseIndex: 0, setIndex: index, exerciseID: UUID(),
            planned: SetValues(reps: 10, kg: 60, restSeconds: 90),
            actualReps: nil, actualKg: nil, status: status, completedAt: completedAt)
    }

    private func snapshot(
        _ statuses: [SetStatus], endedAt: Date? = nil, pausedAt: Date? = nil, status: SessionStatus = .inProgress
    ) -> SessionSnapshot {
        SessionSnapshot(
            startedAt: t0, endedAt: endedAt, pausedAt: pausedAt, status: status, exerciseCount: 1,
            entries: statuses.enumerated().map { entry($1, at: $0, completedAt: $1 == .pending ? nil : t0 + 5) })
    }

    @Test func runningWorkoutWithADoneSetAsksAndCanSave() {
        #expect(LaunchRecovery.decide(snapshot([.done, .pending])) == .askResume(canSave: true))
    }

    @Test func runningWorkoutWithNoDoneSetAsksAndCannotSave() {
        #expect(LaunchRecovery.decide(snapshot([.pending, .pending])) == .askResume(canSave: false))
        #expect(LaunchRecovery.decide(snapshot([.skipped, .pending])) == .askResume(canSave: false))
    }

    @Test func pausedRunningWorkoutAsks() {
        #expect(LaunchRecovery.decide(snapshot([.done, .pending], pausedAt: t0 + 20)) == .askResume(canSave: true))
    }

    @Test func finishedWorkoutWaitingForSaveShowsTheSummary() {
        #expect(LaunchRecovery.decide(snapshot([.done, .done], endedAt: t0 + 30)) == .showSummary)
        #expect(LaunchRecovery.decide(snapshot([.skipped, .skipped], endedAt: t0 + 30)) == .showSummary)
        #expect(LaunchRecovery.decide(snapshot([.done, .notPerformed], endedAt: t0 + 30)) == .showSummary)
    }

    @Test func everySetResolvedWithoutEndedAtShowsTheSummary() {
        #expect(LaunchRecovery.decide(snapshot([.done, .skipped])) == .showSummary)
        #expect(LaunchRecovery.decide(snapshot([.skipped])) == .showSummary)
        #expect(LaunchRecovery.decide(snapshot([])) == .showSummary)
    }

    @Test func savedSessionNeedsNoRecovery() {
        #expect(LaunchRecovery.decide(snapshot([.done], endedAt: t0 + 30, status: .completed)) == .nothingToRecover)
        #expect(LaunchRecovery.decide(snapshot([.done, .notPerformed], endedAt: t0 + 30, status: .endedEarly)) == .nothingToRecover)
    }
}
