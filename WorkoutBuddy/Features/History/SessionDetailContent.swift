import Foundation

/// Everything the session detail shows, as plain values built from a snapshot and the looked-up names.
/// The view keeps this value, never a model, so a deleted session can't be read. Pure, so it can be unit tested.
nonisolated struct SessionDetailContent: Equatable, Sendable {
    /// One set row: "Set 2", "8 × 60 kg", and the plan underneath where it differs.
    struct SetRow: Equatable, Sendable, Identifiable {
        /// The set's ID.
        var id: UUID
        var title: String
        var primaryText: String
        /// "Planned 10 × 60 kg": for a changed, skipped or not-performed set. `nil` for a set done as planned.
        var plannedText: String?
        /// The whole row as one VoiceOver element.
        var spokenText: String
        var status: SetStatus
    }

    /// One exercise of the session.
    struct Section: Equatable, Sendable, Identifiable {
        /// The position of the exercise in the session. Not the exercise ID, which can be `nil` for several.
        var id: Int
        /// Kept for phase 6's link to the progress screen. `nil` when the reference is gone.
        var exerciseID: UUID?
        var name: String
        var rows: [SetRow]
    }

    var workoutName: String
    var startedAt: Date
    var startText: String
    /// "Ended early" for an ended-early session, otherwise `nil`.
    var endedEarlyText: String?
    var durationText: String
    var spokenDurationText: String
    var volumeText: String
    var spokenVolumeText: String
    var sections: [Section]

    /// - Parameters:
    ///   - workoutName: from the template reference (soft-deleted or not); `nil` when it's gone.
    ///   - exerciseNames: `SessionLibrary.exerciseNames(of:)`, by exercise ID.
    init(
        _ snapshot: SessionSnapshot, workoutName: String?, exerciseNames: [UUID: String],
        locale: Locale = .current, timeZone: TimeZone = .current
    ) {
        let stats = SessionStats(snapshot, now: snapshot.endedAt ?? snapshot.startedAt)
        self.workoutName = HistoryMessages.workoutName(workoutName)
        startedAt = snapshot.startedAt
        startText = Formatters.sessionStart(snapshot.startedAt, locale: locale, timeZone: timeZone)
        endedEarlyText = snapshot.status == .endedEarly ? HistoryMessages.endedEarlyText : nil
        durationText = SessionMessages.durationText(stats, locale: locale)
        spokenDurationText = SessionMessages.spokenDurationText(stats, locale: locale)
        volumeText = SessionMessages.volumeText(stats, locale: locale)
        spokenVolumeText = SessionMessages.spokenVolumeText(stats, locale: locale)

        var sections: [Section] = []
        for entry in snapshot.entries {
            if sections.last?.id != entry.exerciseIndex {
                let name = entry.exerciseID.flatMap { exerciseNames[$0] } ?? SessionMessages.fallbackExerciseName
                sections.append(Section(id: entry.exerciseIndex, exerciseID: entry.exerciseID, name: name, rows: []))
            }
            sections[sections.count - 1].rows.append(Self.row(for: entry, locale: locale))
        }
        self.sections = sections
    }

    private static func row(for entry: SessionSnapshot.Entry, locale: Locale) -> SetRow {
        let title = ExerciseSetsRules.sectionTitle(forSetAt: entry.setIndex)
        let planned = entry.planned
        let plannedText = HistoryMessages.plannedText(planned, locale: locale)
        let spokenPlanned = HistoryMessages.spokenPlannedText(planned, locale: locale)

        switch entry.status {
        case .done:
            // A done set always has actual values; the plan is only a defensive fallback.
            let actual = SetValues(
                reps: entry.actualReps ?? planned.reps, kg: entry.actualKg ?? planned.kg, restSeconds: planned.restSeconds)
            let differs = actual.reps != planned.reps || actual.kg != planned.kg
            return SetRow(
                id: entry.id, title: title,
                primaryText: SetSummary.line(actual, locale: locale),
                plannedText: differs ? plannedText : nil,
                spokenText: "\(title), \(SetSummary.spokenLine(actual, locale: locale))"
                    + (differs ? ", \(spokenPlanned)" : ""),
                status: entry.status)
        case .skipped:
            return SetRow(
                id: entry.id, title: title, primaryText: HistoryMessages.skippedText, plannedText: plannedText,
                spokenText: "\(title), skipped, \(spokenPlanned)", status: entry.status)
        case .notPerformed, .pending:
            // A saved session has no pending sets; if one slips through it reads as not performed.
            return SetRow(
                id: entry.id, title: title, primaryText: HistoryMessages.notPerformedText, plannedText: plannedText,
                spokenText: "\(title), not performed, \(spokenPlanned)", status: entry.status)
        }
    }
}
