import Foundation
import Testing
@testable import WorkoutBuddy

struct SessionConfirmationTests {
    private func snapshot(_ statuses: [SetStatus]) -> SessionSnapshot {
        let entries = statuses.enumerated().map { index, status in
            SessionSnapshot.Entry(
                id: UUID(), exerciseIndex: 0, setIndex: index, exerciseID: UUID(),
                planned: SetValues(reps: 10, kg: 60, restSeconds: 90),
                actualReps: nil, actualKg: nil, status: status, completedAt: nil)
        }
        return SessionSnapshot(startedAt: .now, exerciseCount: 1, entries: entries)
    }

    @Test func endTapWithADoneSetAsksToEnd() {
        #expect(SessionConfirmation.forEndTap(in: snapshot([.done, .pending])) == .end)
    }

    @Test func endTapWithNoDoneSetAsksToDiscard() {
        #expect(SessionConfirmation.forEndTap(in: snapshot([.pending, .pending])) == .discard)
        #expect(SessionConfirmation.forEndTap(in: snapshot([.skipped, .pending])) == .discard)
    }

    @Test func texts() {
        #expect(SessionConfirmation.end.title == "End Workout?")
        #expect(SessionConfirmation.end.message == "The remaining sets will be saved as not performed.")
        #expect(SessionConfirmation.end.confirmButton == "End Workout")
        #expect(SessionConfirmation.discard.title == "Discard Workout?")
        #expect(SessionConfirmation.discard.message == "No sets were completed, so nothing will be saved.")
        #expect(SessionConfirmation.discard.confirmButton == "Discard Workout")
    }
}
