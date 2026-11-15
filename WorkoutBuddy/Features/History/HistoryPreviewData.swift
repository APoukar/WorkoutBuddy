import Foundation
import SwiftData

/// Preview helper: saved sessions on several days, built through `SessionLibrary` like the UI-testing scenarios.
/// Builds on `WorkoutPreviewData` ("Push Day", "Legs", "Core"). Compiled in every configuration (no `#if DEBUG`),
/// because a Debug-only helper broke the Release build.
///
/// Order matters: `start` refuses soft-deleted templates and a second session in progress, and archiving removes
/// an exercise from the templates. So every session is started and saved first, oldest first, and only then is
/// the "Core" template soft-deleted and "Leg Press" archived.
@MainActor
enum HistoryPreviewData {
    struct Preview {
        let container: ModelContainer
        /// "Push Day", completed, the evening of two on the same day.
        let completedID: UUID
        /// "Legs", ended early: a changed set, a skipped set and a not-performed set.
        let endedEarlyID: UUID
        /// "Core", completed, with a Bodyweight set; its template is soft-deleted.
        let bodyweightID: UUID
        /// All the saved sessions, oldest first (also "Legs" from `WorkoutPreviewData`).
        let sessionIDs: [UUID]
    }

    static func make() -> Preview {
        let container = WorkoutPreviewData.container()
        let context = container.mainContext
        let library = SessionLibrary(context: context)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        func day(_ offset: Int, hour: Int, minute: Int = 0) -> Date {
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }
        func session(_ name: String, at start: Date) -> WorkoutSession {
            guard let workout = WorkoutPreviewData.workout(named: name, in: container),
                let session = try? library.start(workout, now: start)
            else { fatalError("Preview data: could not start a session of \(name)") }
            return session
        }
        func save(_ session: WorkoutSession) {
            do { try library.save(session) } catch { fatalError("Preview data: could not save a session: \(error)") }
        }

        // Core (Bodyweight), 6 days ago.
        let core = session("Core", at: day(-6, hour: 7, minute: 30))
        var ids = library.snapshot(of: core).entries.map(\.id)
        try? library.completeSet(in: core, setID: ids[0], reps: 15, kg: 0, now: core.startedAt.addingTimeInterval(300))
        try? library.completeSet(in: core, setID: ids[1], reps: 12, kg: 30, now: core.startedAt.addingTimeInterval(700))
        save(core)

        // Legs, ended early, 4 days ago ("Legs" from `WorkoutPreviewData` already has a finished session 3 days ago): set 2 changed, set 3 skipped, the last one never reached.
        let legs = session("Legs", at: day(-4, hour: 18))
        ids = library.snapshot(of: legs).entries.map(\.id)
        try? library.completeSet(in: legs, setID: ids[0], reps: 5, kg: 100, now: legs.startedAt.addingTimeInterval(240))
        try? library.skipRest(in: legs, now: legs.startedAt.addingTimeInterval(250))
        try? library.completeSet(in: legs, setID: ids[1], reps: 4, kg: 105, now: legs.startedAt.addingTimeInterval(600))
        try? library.skipRest(in: legs, now: legs.startedAt.addingTimeInterval(610))
        try? library.skipSet(in: legs, setID: ids[2], now: legs.startedAt.addingTimeInterval(700))
        try? library.endEarly(in: legs, now: legs.startedAt.addingTimeInterval(720))
        save(legs)

        // Push Day twice on the day before: a morning one and an evening one.
        let morning = session("Push Day", at: day(-1, hour: 8))
        ids = library.snapshot(of: morning).entries.map(\.id)
        try? library.completeSet(in: morning, setID: ids[0], reps: 10, kg: 60, now: morning.startedAt.addingTimeInterval(300))
        try? library.completeSet(in: morning, setID: ids[1], reps: 8, kg: 40, now: morning.startedAt.addingTimeInterval(800))
        save(morning)

        let evening = session("Push Day", at: day(-1, hour: 18, minute: 30))
        ids = library.snapshot(of: evening).entries.map(\.id)
        try? library.completeSet(in: evening, setID: ids[0], reps: 8, kg: 62.5, now: evening.startedAt.addingTimeInterval(400))
        try? library.completeSet(in: evening, setID: ids[1], reps: 8, kg: 40, now: evening.startedAt.addingTimeInterval(1000))
        save(evening)

        // Only now: a soft-deleted template and an archived exercise.
        if let template = WorkoutPreviewData.workout(named: "Core", in: container) {
            try? WorkoutLibrary(context: context).softDelete(template)
        }
        if let legPress = WorkoutPreviewData.exercise(named: "Leg Press", in: container) {
            try? ExerciseLibrary(context: context).archive(legPress)
        }

        return Preview(
            container: container, completedID: evening.id, endedEarlyID: legs.id, bodyweightID: core.id,
            sessionIDs: ((try? HistoryLibrary(context: context).finishedSessions()) ?? []).map(\.id))
    }
}
