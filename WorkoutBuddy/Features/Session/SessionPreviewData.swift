import Foundation
import SwiftData

/// Preview helper: starts a session of "Push Day" (Bench Press, then Overhead Press) in a useful state.
/// Builds on `WorkoutPreviewData`, and is compiled in every configuration (no `#if DEBUG`), because a
/// Debug-only helper broke the Release build.
@MainActor
enum SessionPreviewData {
    enum State: CaseIterable, Sendable {
        /// Just started, on the first set.
        case firstSet
        /// The first set is done; the rest before Overhead Press runs.
        case resting
        /// Paused during that rest.
        case paused
        /// Both sets done: the summary with Save.
        case finished
        /// The first set done, the workout ended early: the summary with a not-performed set.
        case endedEarly
        /// Every set skipped: the summary with Discard instead of Save.
        case allSkipped
    }

    struct Preview {
        let container: ModelContainer
        let sessionID: UUID
    }

    /// Times are relative to now, so the timers on screen look right.
    static func make(_ state: State, now: Date = .now) -> Preview {
        let container = WorkoutPreviewData.container()
        let library = SessionLibrary(context: container.mainContext)
        guard let pushDay = WorkoutPreviewData.workout(named: "Push Day", in: container),
            let session = try? library.start(pushDay, now: now.addingTimeInterval(-754))
        else { fatalError("Preview data: could not start a session of Push Day") }
        let sets = library.snapshot(of: session).entries.map(\.id)

        func after(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(seconds) }
        switch state {
        case .firstSet:
            break
        case .resting:
            try? library.completeSet(in: session, setID: sets[0], reps: 10, kg: 60, now: after(-28))
        case .paused:
            try? library.completeSet(in: session, setID: sets[0], reps: 10, kg: 60, now: after(-28))
            try? library.pause(in: session, now: after(-10))
        case .finished:
            try? library.completeSet(in: session, setID: sets[0], reps: 10, kg: 60, now: after(-400))
            try? library.completeSet(in: session, setID: sets[1], reps: 8, kg: 40, now: after(-100))
        case .endedEarly:
            try? library.completeSet(in: session, setID: sets[0], reps: 10, kg: 60, now: after(-200))
            try? library.endEarly(in: session, now: after(-100))
        case .allSkipped:
            try? library.skipSet(in: session, setID: sets[0], now: after(-300))
            try? library.skipSet(in: session, setID: sets[1], now: after(-100))
        }
        return Preview(container: container, sessionID: session.id)
    }
}
