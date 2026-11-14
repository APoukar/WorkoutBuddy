import Foundation
import Testing
@testable import WorkoutBuddy

struct SessionDetailContentTests {
    private let enUS = Locale(identifier: "en_US")
    private let enCZ = Locale(identifier: "en_CZ")
    private let prague = TimeZone(identifier: "Europe/Prague") ?? .gmt

    /// Saturday 14 November 2026, 18:30 in Prague.
    private var start: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = prague
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 18, minute: 30)) ?? .now
    }

    private func entry(
        _ exercise: Int, _ set: Int, id exerciseID: UUID?, planned: (Int, Double), actual: (Int, Double)? = nil,
        status: SetStatus = .done
    ) -> SessionSnapshot.Entry {
        SessionSnapshot.Entry(
            id: UUID(), exerciseIndex: exercise, setIndex: set, exerciseID: exerciseID,
            planned: SetValues(reps: planned.0, kg: planned.1, restSeconds: 90),
            actualReps: actual?.0, actualKg: actual?.1, status: status, completedAt: nil)
    }

    private func content(
        _ entries: [SessionSnapshot.Entry], status: SessionStatus = .completed, name: String? = "Push Day",
        names: [UUID: String] = [:], locale: Locale? = nil, duration: TimeInterval = 3_900
    ) -> SessionDetailContent {
        let snapshot = SessionSnapshot(
            startedAt: start, endedAt: start + duration, status: status,
            exerciseCount: (entries.map(\.exerciseIndex).max() ?? -1) + 1, entries: entries)
        return SessionDetailContent(
            snapshot, workoutName: name, exerciseNames: names, locale: locale ?? enUS, timeZone: prague)
    }

    private func row(_ entry: SessionSnapshot.Entry, locale: Locale? = nil) -> SessionDetailContent.SetRow {
        content([entry], locale: locale).sections[0].rows[0]
    }

    // MARK: Header

    @Test func headerTexts() {
        let content = content([entry(0, 0, id: UUID(), planned: (10, 60), actual: (10, 60))])
        #expect(content.workoutName == "Push Day")
        #expect(content.startText.hasPrefix("Saturday, November 14, 2026 at 6:30"))
        #expect(content.durationText == "1 hr, 5 min")
        #expect(content.spokenDurationText == "1 hour, 5 minutes")
        #expect(content.volumeText == "600\u{00A0}kg")
        #expect(content.spokenVolumeText == "600 kilograms")
        #expect(content.endedEarlyText == nil)
    }

    @Test func headerFollowsTheLocale() {
        let content = content([entry(0, 0, id: UUID(), planned: (10, 22.5), actual: (10, 22.5))], locale: enCZ)
        #expect(content.startText.hasPrefix("Saturday 14 November 2026 at 18:30"))
        #expect(content.volumeText == "225\u{00A0}kg")
    }

    @Test func endedEarlyIsMarked() {
        let sets = [entry(0, 0, id: UUID(), planned: (10, 60), actual: (10, 60)),
                    entry(0, 1, id: UUID(), planned: (10, 60), status: .notPerformed)]
        #expect(content(sets, status: .endedEarly).endedEarlyText == "Ended early")
        #expect(content(sets, status: .completed).endedEarlyText == nil)
    }

    @Test func volumeZeroReadsZeroKg() {
        let content = content([entry(0, 0, id: UUID(), planned: (10, 0), actual: (10, 0))])
        #expect(content.volumeText == "0\u{00A0}kg")
        #expect(content.spokenVolumeText == "0 kilograms")
    }

    @Test func missingWorkoutNameUsesTheFallback() {
        #expect(content([], name: nil).workoutName == "Workout")
        #expect(content([], name: "  ").workoutName == "Workout")
    }

    // MARK: Sets

    @Test func doneAsPlannedHasNoPlanLine() {
        let row = row(entry(0, 1, id: UUID(), planned: (10, 60), actual: (10, 60)))
        #expect(row.title == "Set 2")
        #expect(row.primaryText == "10 × 60\u{00A0}kg")
        #expect(row.plannedText == nil)
        #expect(row.spokenText == "Set 2, 10 reps at 60 kilograms")
    }

    @Test func repsDifferShowsThePlan() {
        let row = row(entry(0, 1, id: UUID(), planned: (10, 60), actual: (8, 60)))
        #expect(row.primaryText == "8 × 60\u{00A0}kg")
        #expect(row.plannedText == "Planned 10 × 60\u{00A0}kg")
        #expect(row.spokenText == "Set 2, 8 reps at 60 kilograms, planned 10 reps at 60 kilograms")
    }

    @Test func kgDiffersShowsThePlan() {
        let row = row(entry(0, 0, id: UUID(), planned: (10, 60), actual: (10, 62.5)))
        #expect(row.primaryText == "10 × 62.5\u{00A0}kg")
        #expect(row.plannedText == "Planned 10 × 60\u{00A0}kg")
    }

    @Test func bothDifferShowsThePlan() {
        let row = row(entry(0, 0, id: UUID(), planned: (10, 60), actual: (1, 1)))
        #expect(row.primaryText == "1 × 1\u{00A0}kg")
        #expect(row.plannedText == "Planned 10 × 60\u{00A0}kg")
        #expect(row.spokenText == "Set 1, 1 rep at 1 kilogram, planned 10 reps at 60 kilograms")
    }

    @Test func restIsNotCompared() {
        var e = entry(0, 0, id: UUID(), planned: (10, 60), actual: (10, 60))
        e.planned.restSeconds = 30
        #expect(row(e).plannedText == nil)
    }

    @Test func skippedSet() {
        let row = row(entry(0, 2, id: UUID(), planned: (8, 62.5), status: .skipped))
        #expect(row.primaryText == "Skipped")
        #expect(row.plannedText == "Planned 8 × 62.5\u{00A0}kg")
        #expect(row.spokenText == "Set 3, skipped, planned 8 reps at 62.5 kilograms")
        #expect(row.status == .skipped)
    }

    @Test func notPerformedSet() {
        let row = row(entry(0, 3, id: UUID(), planned: (8, 62.5), status: .notPerformed))
        #expect(row.primaryText == "Not performed")
        #expect(row.plannedText == "Planned 8 × 62.5\u{00A0}kg")
        #expect(row.spokenText == "Set 4, not performed, planned 8 reps at 62.5 kilograms")
    }

    @Test func pendingSetInASavedSessionReadsNotPerformed() {
        let row = row(entry(0, 0, id: UUID(), planned: (8, 62.5), status: .pending))
        #expect(row.primaryText == "Not performed")
        #expect(row.plannedText == "Planned 8 × 62.5\u{00A0}kg")
        #expect(row.spokenText == "Set 1, not performed, planned 8 reps at 62.5 kilograms")
    }

    @Test func bodyweightActualAndPlanned() {
        let same = row(entry(0, 0, id: UUID(), planned: (12, 0), actual: (12, 0)))
        #expect(same.primaryText == "12 × Bodyweight")
        #expect(same.plannedText == nil)
        #expect(same.spokenText == "Set 1, 12 reps, bodyweight")

        let added = row(entry(0, 0, id: UUID(), planned: (12, 0), actual: (12, 10)))
        #expect(added.primaryText == "12 × 10\u{00A0}kg")
        #expect(added.plannedText == "Planned 12 × Bodyweight")
        #expect(added.spokenText == "Set 1, 12 reps at 10 kilograms, planned 12 reps, bodyweight")

        let skipped = row(entry(0, 0, id: UUID(), planned: (12, 0), status: .skipped))
        #expect(skipped.plannedText == "Planned 12 × Bodyweight")
    }

    @Test func weightsFollowTheLocale() {
        let row = row(entry(0, 0, id: UUID(), planned: (10, 60), actual: (10, 22.5)), locale: enCZ)
        #expect(row.primaryText == "10 × 22,5\u{00A0}kg")
    }

    // MARK: Sections

    @Test func sectionsFollowTheSessionOrderAndNames() {
        let bench = UUID(), row = UUID()
        let entries = [
            entry(0, 0, id: bench, planned: (10, 60), actual: (10, 60)),
            entry(0, 1, id: bench, planned: (10, 60), actual: (10, 60)),
            entry(1, 0, id: row, planned: (8, 50), actual: (8, 50)),
        ]
        let content = content(entries, names: [bench: "Bench Press", row: "Row"])
        #expect(content.sections.map(\.name) == ["Bench Press", "Row"])
        #expect(content.sections.map(\.id) == [0, 1])
        #expect(content.sections.map(\.exerciseID) == [bench, row])
        #expect(content.sections[0].rows.map(\.title) == ["Set 1", "Set 2"])
        #expect(content.sections[0].rows.map(\.id) == entries[0...1].map(\.id))
        #expect(content.sections[1].rows.map(\.title) == ["Set 1"])
    }

    @Test func missingExerciseNamesUseTheFallbackAndSectionsStayApart() {
        let known = UUID()
        let entries = [
            entry(0, 0, id: nil, planned: (10, 60), actual: (10, 60)),
            entry(1, 0, id: nil, planned: (10, 60), actual: (10, 60)),
            entry(2, 0, id: UUID(), planned: (10, 60), actual: (10, 60)),
            entry(3, 0, id: known, planned: (10, 60), actual: (10, 60)),
        ]
        let content = content(entries, names: [known: "Squat"])
        #expect(content.sections.map(\.name) == ["Exercise", "Exercise", "Exercise", "Squat"])
        #expect(content.sections.map(\.id) == [0, 1, 2, 3])
        #expect(content.sections[0].exerciseID == nil)
    }

    @Test func sessionWithoutSetsHasNoSections() {
        #expect(content([]).sections.isEmpty)
    }
}
