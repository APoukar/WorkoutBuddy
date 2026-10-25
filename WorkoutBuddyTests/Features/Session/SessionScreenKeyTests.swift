import Foundation
import Testing
@testable import WorkoutBuddy

struct SessionScreenKeyTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func snapshot(statuses: [SetStatus], restEndsAt: Date? = nil, endedAt: Date? = nil) -> SessionSnapshot {
        let entries = statuses.enumerated().map { index, status in
            SessionSnapshot.Entry(
                id: UUID(), exerciseIndex: 0, setIndex: index, exerciseID: UUID(),
                planned: SetValues(reps: 10, kg: 60, restSeconds: 90),
                actualReps: nil, actualKg: nil, status: status, completedAt: nil)
        }
        return SessionSnapshot(
            startedAt: t0, endedAt: endedAt, restEndsAt: restEndsAt, exerciseCount: 1, entries: entries)
    }

    @Test func setScreenKeyIsTheSetID() {
        let snapshot = snapshot(statuses: [.done, .pending])
        let key = SessionScreenKey(snapshot.screen(now: t0), in: snapshot)
        #expect(key == .set(snapshot.entries[1].id))
    }

    @Test func restKeyIsTheNextSetAndDoesNotChangeEverySecond() {
        let snapshot = snapshot(statuses: [.done, .pending], restEndsAt: t0 + 90)
        let first = snapshot.screen(now: t0)
        let later = snapshot.screen(now: t0 + 30)
        #expect(first != later)  // the screen value carries the remaining seconds
        #expect(SessionScreenKey(first, in: snapshot) == .rest(snapshot.entries[1].id))
        #expect(SessionScreenKey(first, in: snapshot) == SessionScreenKey(later, in: snapshot))
    }

    @Test func restAndSetScreensOfTheSameSetDiffer() {
        let resting = snapshot(statuses: [.done, .pending], restEndsAt: t0 + 90)
        let expired = resting.screen(now: t0 + 100)
        #expect(SessionScreenKey(resting.screen(now: t0), in: resting) != SessionScreenKey(expired, in: resting))
    }

    @Test func summaryKey() {
        let snapshot = snapshot(statuses: [.done, .done], endedAt: t0 + 60)
        #expect(SessionScreenKey(snapshot.screen(now: t0 + 61), in: snapshot) == .summary)
    }
}
