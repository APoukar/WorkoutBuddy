import Foundation
import SwiftData

/// Seeds the data of a UI-testing scenario, using the app's own `WorkoutLibrary` and `SessionLibrary`.
/// Unlike `SessionPreviewData`, every call is `try`, and the caller stops the app on failure, so a scenario
/// can never silently start in the wrong state. The library ignores actions that don't apply (Skip Set while
/// a rest runs does nothing), so the session scenarios clear the rest with `skipRest` between actions.
/// Compiled in every configuration (no `#if DEBUG`), like the preview data.
@MainActor
enum UITestingScenario {
    enum SeedError: Error, CustomStringConvertible {
        case missingExercise(String)

        var description: String {
            switch self {
            case .missingExercise(let name): "built-in exercise '\(name)' not found"
            }
        }
    }

    /// The planned sets of both templates: Bench Press 10 x 60 and 8 x 62.5, Overhead Press 8 x 40.
    /// Completing all three as planned gives a volume of 1,420 kg.
    private static func draft(name: String, rests: [Int], bench: Exercise, press: Exercise) -> WorkoutDraft {
        WorkoutDraft(
            name: name,
            exercises: [
                DraftExercise(
                    exerciseID: bench.id,
                    sets: [
                        DraftSet(values: SetValues(reps: 10, kg: 60, restSeconds: rests[0])),
                        DraftSet(values: SetValues(reps: 8, kg: 62.5, restSeconds: rests[1])),
                    ]),
                DraftExercise(
                    exerciseID: press.id,
                    sets: [DraftSet(values: SetValues(reps: 8, kg: 40, restSeconds: rests[2]))]),
            ])
    }

    /// Seeds the scenario into a store that already has the exercise seed. `now` is the launch time; running
    /// sessions are dated a few minutes before it. Call it only on a fresh store.
    static func seed(_ scenario: UITestingLaunch.Scenario, in container: ModelContainer, now: Date = .now) throws {
        if scenario == .empty { return }

        let context = container.mainContext
        guard let bench = WorkoutPreviewData.exercise(named: "Bench Press", in: container) else {
            throw SeedError.missingExercise("Bench Press")
        }
        guard let press = WorkoutPreviewData.exercise(named: "Overhead Press", in: container) else {
            throw SeedError.missingExercise("Overhead Press")
        }
        let workouts = WorkoutLibrary(context: context)
        let created = now.addingTimeInterval(-3600)
        _ = try workouts.save(
            draft(name: UITestingContract.Workout.shortRests, rests: [10, 0, 10], bench: bench, press: press),
            to: nil, now: created)
        let longRests = try workouts.save(
            draft(name: UITestingContract.Workout.longRests, rests: [600, 600, 600], bench: bench, press: press),
            to: nil, now: created)

        let sessions = SessionLibrary(context: context)
        func at(_ secondsBeforeNow: TimeInterval) -> Date { now.addingTimeInterval(-secondsBeforeNow) }

        switch scenario {
        case .empty, .templates:
            break
        case .inProgress:
            // First set done, second skipped, the current set is Overhead Press.
            let session = try sessions.start(longRests, now: at(300))
            let sets = sessions.snapshot(of: session).entries.map(\.id)
            try sessions.completeSet(in: session, setID: sets[0], reps: 10, kg: 60, now: at(240))
            try sessions.skipRest(in: session, now: at(235))
            try sessions.skipSet(in: session, setID: sets[1], now: at(230))
        case .nothingDone:
            let session = try sessions.start(longRests, now: at(300))
            let sets = sessions.snapshot(of: session).entries.map(\.id)
            try sessions.skipSet(in: session, setID: sets[0], now: at(240))
        case .onSummary:
            // All three sets done as planned, the workout finished and waiting for Save.
            let session = try sessions.start(longRests, now: at(600))
            let sets = sessions.snapshot(of: session).entries.map(\.id)
            try sessions.completeSet(in: session, setID: sets[0], reps: 10, kg: 60, now: at(500))
            try sessions.skipRest(in: session, now: at(495))
            try sessions.completeSet(in: session, setID: sets[1], reps: 8, kg: 62.5, now: at(400))
            try sessions.skipRest(in: session, now: at(395))
            try sessions.completeSet(in: session, setID: sets[2], reps: 8, kg: 40, now: at(300))
        case .history:
            try seedHistory(longRests, sessions: sessions, now: now)
        }
    }

    /// Saved "Long Rests" sessions: two today and one on the 15th of the previous month.
    ///
    /// Midnight-safe: today's sessions are anchored at `max(start of today, now - 2 h)` plus fixed offsets, so
    /// they stay on today even right after midnight. Their actions may then come after `now`; `SessionLibrary`
    /// accepts any `now:`. The older one is on the previous month's 15th (that month always has one), in the
    /// evening, so it is always in the past.
    private static func seedHistory(_ workout: Workout, sessions: SessionLibrary, now: Date) throws {
        let calendar = Calendar.current
        let anchor = max(calendar.startOfDay(for: now), now.addingTimeInterval(-2 * 3600))

        // The 15th of the previous month: set 1 done with a changed kg, set 2 skipped, set 3 never reached.
        let fifteenth = UITestingContract.History.previousMonthFifteenth(now: now, calendar: calendar)
        let old = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: fifteenth) ?? fifteenth
        func fromOld(_ seconds: TimeInterval) -> Date { old.addingTimeInterval(seconds) }
        let early = try sessions.start(workout, now: old)
        var sets = sessions.snapshot(of: early).entries.map(\.id)
        try sessions.completeSet(in: early, setID: sets[0], reps: 10, kg: 65, now: fromOld(120))
        try sessions.skipRest(in: early, now: fromOld(125))
        try sessions.skipSet(in: early, setID: sets[1], now: fromOld(200))
        try sessions.endEarly(in: early, now: fromOld(260))
        try sessions.save(early)

        // Two today, all sets done as planned (volume 1,420 kg): one at the anchor, one half an hour later.
        for offset: TimeInterval in [0, 1800] {
            func at(_ seconds: TimeInterval) -> Date { anchor.addingTimeInterval(offset + seconds) }
            let session = try sessions.start(workout, now: at(0))
            sets = sessions.snapshot(of: session).entries.map(\.id)
            try sessions.completeSet(in: session, setID: sets[0], reps: 10, kg: 60, now: at(100))
            try sessions.skipRest(in: session, now: at(105))
            try sessions.completeSet(in: session, setID: sets[1], reps: 8, kg: 62.5, now: at(200))
            try sessions.skipRest(in: session, now: at(205))
            try sessions.completeSet(in: session, setID: sets[2], reps: 8, kg: 40, now: at(300))
            try sessions.save(session)
        }
    }
}
