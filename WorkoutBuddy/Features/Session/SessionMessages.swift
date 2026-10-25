import Foundation

/// User-facing texts for the session screens. Pure, so it can be unit tested. Texts that VoiceOver
/// reads differently from how they look have a spoken form. Names are never stored in a session,
/// so the caller looks them up from the references and passes them in.
nonisolated enum SessionMessages {
    // MARK: Screen labels

    static let elapsedTimeLabel = "Elapsed time"
    static let pauseLabel = "Pause"
    static let doneButton = "Done"
    static let skipSetButton = "Skip Set"
    static let restTitle = "Rest"
    static let restRemainingLabel = "Rest remaining"
    /// Small caption under the countdown's number in the ring; VoiceOver reads `restRemainingLabel` instead.
    static let restRemainingCaption = "Remaining"
    static let upNextTitle = "Up next"
    static let skipRestButton = "Skip Rest"
    static let undoButton = "Undo"
    static let pausedTitle = "Paused"
    static let resumeButton = "Resume"
    static let cancelButton = "Cancel"

    // MARK: Positions

    /// "Exercise 2 of 5". `index` is zero-based.
    static func exercisePosition(index: Int, count: Int) -> String {
        "Exercise \(index + 1) of \(count)"
    }

    /// "Set 3 of 4". `index` is zero-based.
    static func setPosition(index: Int, count: Int) -> String {
        "Set \(index + 1) of \(count)"
    }

    /// "Exercise 2 of 5 · Set 3 of 4", for the set at `index` in `snapshot.entries`.
    static func position(of index: Int, in snapshot: SessionSnapshot) -> String {
        let entry = snapshot.entries[index]
        return "\(exercisePosition(index: entry.exerciseIndex, count: snapshot.exerciseCount)) · "
            + setPosition(index: entry.setIndex, count: snapshot.setCount(ofExercise: entry.exerciseIndex))
    }

    /// "Exercise 2 of 5, set 3 of 4".
    static func spokenPosition(of index: Int, in snapshot: SessionSnapshot) -> String {
        let entry = snapshot.entries[index]
        let setCount = snapshot.setCount(ofExercise: entry.exerciseIndex)
        return "\(exercisePosition(index: entry.exerciseIndex, count: snapshot.exerciseCount)), set \(entry.setIndex + 1) of \(setCount)"
    }

    // MARK: Next set and up next

    static let lastSet = "Last set"

    /// The set screen's preview of the set after the one at `index`: "Next: Set 4 · 10 × 60 kg" within
    /// the same exercise, "Next: Overhead Press · 8 × 40 kg" for the next exercise, "Last set" when
    /// none is left. `nextExerciseName` is only used when the next set belongs to another exercise.
    static func nextPreview(
        after index: Int, in snapshot: SessionSnapshot, nextExerciseName: String?, locale: Locale = .current
    ) -> String {
        guard snapshot.entries.indices.contains(index + 1) else { return lastSet }
        let entry = snapshot.entries[index + 1]
        let line = SetSummary.line(entry.planned, locale: locale)
        if startsNewExercise(at: index + 1, in: snapshot) {
            return "Next: \(nextExerciseName ?? fallbackExerciseName) · \(line)"
        }
        return "Next: Set \(entry.setIndex + 1) · \(line)"
    }

    /// Spoken form: "Next: set 4, 10 reps at 60 kilograms", "Next: Overhead Press, 8 reps at 40 kilograms".
    static func spokenNextPreview(
        after index: Int, in snapshot: SessionSnapshot, nextExerciseName: String?, locale: Locale = .current
    ) -> String {
        guard snapshot.entries.indices.contains(index + 1) else { return lastSet }
        let entry = snapshot.entries[index + 1]
        let line = SetSummary.spokenLine(entry.planned, locale: locale)
        if startsNewExercise(at: index + 1, in: snapshot) {
            return "Next: \(nextExerciseName ?? fallbackExerciseName), \(line)"
        }
        return "Next: set \(entry.setIndex + 1), \(line)"
    }

    /// The rest screen's "Up next" line for the set at `index`. It always names the exercise:
    /// "Bench Press · Set 2 · 8 × 62.5 kg".
    static func upNext(
        at index: Int, in snapshot: SessionSnapshot, exerciseName: String?, locale: Locale = .current
    ) -> String {
        let entry = snapshot.entries[index]
        return "\(exerciseName ?? fallbackExerciseName) · Set \(entry.setIndex + 1) · "
            + SetSummary.line(entry.planned, locale: locale)
    }

    /// Spoken form of `upNext`: "Bench Press, set 2, 8 reps at 62.5 kilograms".
    static func spokenUpNext(
        at index: Int, in snapshot: SessionSnapshot, exerciseName: String?, locale: Locale = .current
    ) -> String {
        let entry = snapshot.entries[index]
        return "\(exerciseName ?? fallbackExerciseName), set \(entry.setIndex + 1), "
            + SetSummary.spokenLine(entry.planned, locale: locale)
    }

    /// Used when the exercise reference is gone and no name can be looked up.
    static let fallbackExerciseName = "Exercise"
    /// Used when the template reference is gone and no workout name can be looked up.
    static let fallbackWorkoutName = "Workout"

    private static func startsNewExercise(at index: Int, in snapshot: SessionSnapshot) -> Bool {
        guard index > 0 else { return true }
        return snapshot.entries[index - 1].exerciseIndex != snapshot.entries[index].exerciseIndex
    }

    // MARK: Summary

    /// "Workout Complete", or "Workout Ended" when the workout was ended early.
    static func summaryTitle(endedEarly: Bool) -> String {
        endedEarly ? "Workout Ended" : "Workout Complete"
    }

    static let saveButton = "Save"
    static let durationLabel = "Duration"
    static let setsLabel = "Sets"
    static let volumeLabel = "Volume"

    /// "8 completed". Singular and plural read the same.
    static func completedText(_ count: Int) -> String { "\(count) completed" }
    static func skippedText(_ count: Int) -> String { "\(count) skipped" }
    static func notPerformedText(_ count: Int) -> String { "\(count) not performed" }

    /// "8 sets completed", "1 set skipped", "3 sets not performed".
    static func spokenCompletedText(_ count: Int) -> String { "\(SetSummary.count(count, "set")) completed" }
    static func spokenSkippedText(_ count: Int) -> String { "\(SetSummary.count(count, "set")) skipped" }
    static func spokenNotPerformedText(_ count: Int) -> String { "\(SetSummary.count(count, "set")) not performed" }

    /// One row of set counts on the summary.
    struct CountLine: Equatable, Sendable {
        var text: String
        var spokenText: String
    }

    /// The count rows to show: completed always, skipped and not performed only when above 0.
    static func countLines(for stats: SessionStats) -> [CountLine] {
        var lines = [CountLine(text: completedText(stats.doneCount), spokenText: spokenCompletedText(stats.doneCount))]
        if stats.skippedCount > 0 {
            lines.append(CountLine(text: skippedText(stats.skippedCount), spokenText: spokenSkippedText(stats.skippedCount)))
        }
        if stats.notPerformedCount > 0 {
            lines.append(CountLine(
                text: notPerformedText(stats.notPerformedCount), spokenText: spokenNotPerformedText(stats.notPerformedCount)))
        }
        return lines
    }

    /// "1 hr, 5 min" for the summary's duration.
    static func durationText(_ stats: SessionStats, locale: Locale = .current) -> String {
        Formatters.duration(seconds: Int(stats.duration), locale: locale)
    }

    static func spokenDurationText(_ stats: SessionStats, locale: Locale = .current) -> String {
        Formatters.spokenWorkoutDuration(seconds: Int(stats.duration), locale: locale)
    }

    /// "4,250 kg" for the summary's total volume.
    static func volumeText(_ stats: SessionStats, locale: Locale = .current) -> String {
        Formatters.volume(stats.volume, locale: locale)
    }

    static func spokenVolumeText(_ stats: SessionStats, locale: Locale = .current) -> String {
        Formatters.spokenVolume(stats.volume, locale: locale)
    }

    /// Above the Discard button when no set was completed.
    static let cannotSaveNote = "No sets were completed, so this workout can't be saved."

    // MARK: Confirmations

    static let endTitle = "End Workout?"
    static let endMessage = "The remaining sets will be saved as not performed."
    static let endButton = "End Workout"

    static let discardTitle = "Discard Workout?"
    static let discardMessage = "No sets were completed, so nothing will be saved."
    static let discardButton = "Discard Workout"

    // MARK: Recovery

    static let recoveryTitle = "Resume Workout?"
    static let recoveryResumeButton = "Resume"
    static let recoveryEndAndSaveButton = "End & Save"
    static let recoveryDiscardButton = "Discard"

    /// "“Push Day” was still in progress.", or "Your workout was still in progress." when there's no name
    /// (the template reference is gone). The name comes from the reference, soft-deleted or not.
    static func recoveryMessage(workoutName: String?) -> String {
        guard let workoutName, !workoutName.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "Your workout was still in progress."
        }
        return "\u{201C}\(workoutName)\u{201D} was still in progress."
    }

    // MARK: Errors

    static func message(for error: SessionError) -> String {
        switch error {
        case .alreadyActive: "A workout is already in progress."
        case .cannotStart: "This workout can't be started."
        }
    }

    /// Text for the error alert after a failed action.
    static func failureMessage(for error: Error) -> String {
        if let sessionError = error as? SessionError { return message(for: sessionError) }
        return ErrorMessages.generic
    }
}
