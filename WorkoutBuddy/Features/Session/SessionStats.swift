import Foundation

/// Counts, volume and duration of a session, computed from a snapshot. Pure, so it can be unit tested.
nonisolated struct SessionStats: Equatable, Sendable {
    let doneCount: Int
    let skippedCount: Int
    let notPerformedCount: Int
    /// Σ actual reps × actual kg over the done sets. Skipped and not-performed sets don't count, and
    /// Bodyweight (0 kg) sets add 0.
    let volume: Double
    /// Time spent working out, excluding pauses. Frozen at `endedAt` once the session is finished,
    /// so `now` only matters for a session that is still running.
    let duration: TimeInterval

    init(_ snapshot: SessionSnapshot, now: Date) {
        var done = 0, skipped = 0, notPerformed = 0
        var volume = 0.0
        for entry in snapshot.entries {
            switch entry.status {
            case .done:
                done += 1
                // A done set always has actual values; the plan is only a defensive fallback.
                volume += Double(entry.actualReps ?? entry.planned.reps) * (entry.actualKg ?? entry.planned.kg)
            case .skipped: skipped += 1
            case .notPerformed: notPerformed += 1
            case .pending: break
            }
        }
        doneCount = done
        skippedCount = skipped
        notPerformedCount = notPerformed
        self.volume = volume
        duration = snapshot.elapsed(now: now)
    }

    /// The workout was ended before the end: some sets were left as not performed.
    var endedEarly: Bool { notPerformedCount > 0 }

    /// A workout with no done set is never saved (F3 end-early rule, applied to the natural end too).
    var canSave: Bool { doneCount > 0 }
}
