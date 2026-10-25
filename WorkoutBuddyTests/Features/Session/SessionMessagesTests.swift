import Foundation
import Testing
@testable import WorkoutBuddy

struct SessionMessagesTests {
    private let us = Locale(identifier: "en_US")
    private let enCZ = Locale(identifier: "en_CZ")
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// Exercise 0: sets 10 x 60 and 8 x 62.5. Exercise 1: one bodyweight set. Exercise 2: one 8 x 22.5 set.
    private func makeSnapshot() -> SessionSnapshot {
        let layout: [(Int, Int, SetValues)] = [
            (0, 0, SetValues(reps: 10, kg: 60, restSeconds: 90)),
            (0, 1, SetValues(reps: 8, kg: 62.5, restSeconds: 90)),
            (1, 0, SetValues(reps: 15, kg: 0, restSeconds: 60)),
            (2, 0, SetValues(reps: 8, kg: 22.5, restSeconds: 60)),
        ]
        let entries = layout.map { exercise, set, planned in
            SessionSnapshot.Entry(
                id: UUID(), exerciseIndex: exercise, setIndex: set, exerciseID: UUID(), planned: planned,
                actualReps: nil, actualKg: nil, status: .pending, completedAt: nil)
        }
        return SessionSnapshot(startedAt: t0, exerciseCount: 3, entries: entries)
    }

    private func stats(done: Int = 0, skipped: Int = 0, notPerformed: Int = 0, volumeKg: Double = 0, seconds: Int = 0) -> SessionStats {
        let planned = SetValues(reps: 10, kg: 60, restSeconds: 90)
        var entries: [SessionSnapshot.Entry] = []
        func add(_ status: SetStatus, _ count: Int, reps: Int? = nil, kg: Double? = nil) {
            for _ in 0..<count {
                entries.append(SessionSnapshot.Entry(
                    id: UUID(), exerciseIndex: 0, setIndex: entries.count, exerciseID: UUID(), planned: planned,
                    actualReps: reps, actualKg: kg, status: status, completedAt: nil))
            }
        }
        // The first done set carries all the volume, the rest are bodyweight.
        if done > 0 { add(.done, 1, reps: 1, kg: volumeKg) }
        if done > 1 { add(.done, done - 1, reps: 10, kg: 0) }
        add(.skipped, skipped)
        add(.notPerformed, notPerformed)
        let snapshot = SessionSnapshot(
            startedAt: t0, endedAt: t0.addingTimeInterval(TimeInterval(seconds)), exerciseCount: 1, entries: entries)
        return SessionStats(snapshot, now: t0)
    }

    // MARK: Positions

    @Test func positions() {
        #expect(SessionMessages.exercisePosition(index: 1, count: 5) == "Exercise 2 of 5")
        #expect(SessionMessages.setPosition(index: 2, count: 4) == "Set 3 of 4")
        let snapshot = makeSnapshot()
        #expect(SessionMessages.position(of: 1, in: snapshot) == "Exercise 1 of 3 · Set 2 of 2")
        #expect(SessionMessages.position(of: 3, in: snapshot) == "Exercise 3 of 3 · Set 1 of 1")
        #expect(SessionMessages.spokenPosition(of: 1, in: snapshot) == "Exercise 1 of 3, set 2 of 2")
    }

    // MARK: Next and up next

    @Test func nextPreviewWithinTheSameExercise() {
        let snapshot = makeSnapshot()
        let text = SessionMessages.nextPreview(after: 0, in: snapshot, nextExerciseName: "Ignored", locale: us)
        #expect(text == "Next: Set 2 · 8 × 62.5\u{00A0}kg")
        #expect(SessionMessages.spokenNextPreview(after: 0, in: snapshot, nextExerciseName: "Ignored", locale: us)
            == "Next: set 2, 8 reps at 62.5 kilograms")
    }

    @Test func nextPreviewForTheNextExercise() {
        let snapshot = makeSnapshot()
        #expect(SessionMessages.nextPreview(after: 2, in: snapshot, nextExerciseName: "Overhead Press", locale: us)
            == "Next: Overhead Press · 8 × 22.5\u{00A0}kg")
        #expect(SessionMessages.spokenNextPreview(after: 2, in: snapshot, nextExerciseName: "Overhead Press", locale: us)
            == "Next: Overhead Press, 8 reps at 22.5 kilograms")
    }

    @Test func nextPreviewReadsBodyweight() {
        let snapshot = makeSnapshot()
        #expect(SessionMessages.nextPreview(after: 1, in: snapshot, nextExerciseName: "Push-up", locale: us)
            == "Next: Push-up · 15 × Bodyweight")
        #expect(SessionMessages.spokenNextPreview(after: 1, in: snapshot, nextExerciseName: "Push-up", locale: us)
            == "Next: Push-up, 15 reps, bodyweight")
    }

    @Test func nextPreviewUsesTheLocaleForNumbers() {
        let snapshot = makeSnapshot()
        #expect(SessionMessages.nextPreview(after: 2, in: snapshot, nextExerciseName: "Press", locale: enCZ)
            == "Next: Press · 8 × 22,5\u{00A0}kg")
    }

    @Test func nextPreviewOfTheLastSet() {
        let snapshot = makeSnapshot()
        #expect(SessionMessages.nextPreview(after: 3, in: snapshot, nextExerciseName: nil) == "Last set")
        #expect(SessionMessages.spokenNextPreview(after: 3, in: snapshot, nextExerciseName: nil) == "Last set")
    }

    @Test func nextPreviewFallsBackWithoutAName() {
        let snapshot = makeSnapshot()
        #expect(SessionMessages.nextPreview(after: 2, in: snapshot, nextExerciseName: nil, locale: us)
            == "Next: Exercise · 8 × 22.5\u{00A0}kg")
        #expect(SessionMessages.spokenNextPreview(after: 2, in: snapshot, nextExerciseName: nil, locale: us)
            == "Next: Exercise, 8 reps at 22.5 kilograms")
    }

    @Test func upNextAlwaysNamesTheExercise() {
        let snapshot = makeSnapshot()
        #expect(SessionMessages.upNext(at: 1, in: snapshot, exerciseName: "Bench Press", locale: us)
            == "Bench Press · Set 2 · 8 × 62.5\u{00A0}kg")
        #expect(SessionMessages.upNext(at: 2, in: snapshot, exerciseName: "Push-up", locale: us)
            == "Push-up · Set 1 · 15 × Bodyweight")
        #expect(SessionMessages.upNext(at: 0, in: snapshot, exerciseName: "Bench Press", locale: us)
            == "Bench Press · Set 1 · 10 × 60\u{00A0}kg")
        #expect(SessionMessages.upNext(at: 3, in: snapshot, exerciseName: "Press", locale: enCZ)
            == "Press · Set 1 · 8 × 22,5\u{00A0}kg")
        #expect(SessionMessages.upNext(at: 1, in: snapshot, exerciseName: nil, locale: us)
            == "Exercise · Set 2 · 8 × 62.5\u{00A0}kg")
        #expect(SessionMessages.spokenUpNext(at: 1, in: snapshot, exerciseName: "Bench Press", locale: us)
            == "Bench Press, set 2, 8 reps at 62.5 kilograms")
        #expect(SessionMessages.spokenUpNext(at: 2, in: snapshot, exerciseName: "Push-up", locale: us)
            == "Push-up, set 1, 15 reps, bodyweight")
        #expect(SessionMessages.spokenUpNext(at: 1, in: snapshot, exerciseName: nil, locale: us)
            == "Exercise, set 2, 8 reps at 62.5 kilograms")
    }

    // MARK: Summary

    @Test func summaryTitle() {
        #expect(SessionMessages.summaryTitle(endedEarly: false) == "Workout Complete")
        #expect(SessionMessages.summaryTitle(endedEarly: true) == "Workout Ended")
    }

    @Test func countTextsAndSingulars() {
        #expect(SessionMessages.completedText(8) == "8 completed")
        #expect(SessionMessages.skippedText(1) == "1 skipped")
        #expect(SessionMessages.notPerformedText(3) == "3 not performed")
        #expect(SessionMessages.spokenCompletedText(8) == "8 sets completed")
        #expect(SessionMessages.spokenCompletedText(1) == "1 set completed")
        #expect(SessionMessages.spokenSkippedText(1) == "1 set skipped")
        #expect(SessionMessages.spokenSkippedText(2) == "2 sets skipped")
        #expect(SessionMessages.spokenNotPerformedText(1) == "1 set not performed")
        #expect(SessionMessages.spokenNotPerformedText(3) == "3 sets not performed")
    }

    @Test func countLinesShowOnlyWhatHappened() {
        let all = SessionMessages.countLines(for: stats(done: 8, skipped: 1, notPerformed: 3))
        #expect(all.map(\.text) == ["8 completed", "1 skipped", "3 not performed"])
        #expect(all.map(\.spokenText) == ["8 sets completed", "1 set skipped", "3 sets not performed"])
        #expect(SessionMessages.countLines(for: stats(done: 1)).map(\.text) == ["1 completed"])
        #expect(SessionMessages.countLines(for: stats(done: 2, skipped: 2)).map(\.text) == ["2 completed", "2 skipped"])
        #expect(SessionMessages.countLines(for: stats(skipped: 3)).map(\.text) == ["0 completed", "3 skipped"])
    }

    @Test func durationAndVolumeTexts() {
        let summary = stats(done: 2, volumeKg: 4250, seconds: 3900)
        #expect(SessionMessages.durationText(summary, locale: us) == "1 hr, 5 min")
        #expect(SessionMessages.spokenDurationText(summary, locale: us) == "1 hour, 5 minutes")
        #expect(SessionMessages.volumeText(summary, locale: us) == "4,250\u{00A0}kg")
        #expect(SessionMessages.volumeText(summary, locale: enCZ) == "4\u{00A0}250\u{00A0}kg")
        #expect(SessionMessages.spokenVolumeText(summary, locale: us) == "4,250 kilograms")
    }

    @Test func zeroVolumeReadsZeroKgNotBodyweight() {
        let summary = stats(done: 1, volumeKg: 0, seconds: 45)
        #expect(SessionMessages.volumeText(summary, locale: us) == "0\u{00A0}kg")
        #expect(SessionMessages.spokenVolumeText(summary, locale: us) == "0 kilograms")
        #expect(SessionMessages.durationText(summary, locale: us) == "45 sec")
    }

    @Test func cannotSaveNote() {
        #expect(SessionMessages.cannotSaveNote == "No sets were completed, so this workout can't be saved.")
    }

    // MARK: Confirmations and recovery

    @Test func confirmationTexts() {
        #expect(SessionMessages.endTitle == "End Workout?")
        #expect(SessionMessages.endMessage == "The remaining sets will be saved as not performed.")
        #expect(SessionMessages.endButton == "End Workout")
        #expect(SessionMessages.discardTitle == "Discard Workout?")
        #expect(SessionMessages.discardMessage == "No sets were completed, so nothing will be saved.")
        #expect(SessionMessages.discardButton == "Discard Workout")
    }

    @Test func recoveryTexts() {
        #expect(SessionMessages.recoveryTitle == "Resume Workout?")
        #expect(SessionMessages.recoveryResumeButton == "Resume")
        #expect(SessionMessages.recoveryEndAndSaveButton == "End & Save")
        #expect(SessionMessages.recoveryDiscardButton == "Discard")
        #expect(SessionMessages.recoveryMessage(workoutName: "Push Day") == "\u{201C}Push Day\u{201D} was still in progress.")
    }

    @Test func recoveryMessageFallsBackWithoutAName() {
        #expect(SessionMessages.recoveryMessage(workoutName: nil) == "Your workout was still in progress.")
        #expect(SessionMessages.recoveryMessage(workoutName: "  ") == "Your workout was still in progress.")
    }

    // MARK: Errors

    @Test func errorMessages() {
        #expect(SessionMessages.message(for: .alreadyActive) == "A workout is already in progress.")
        #expect(SessionMessages.message(for: .cannotStart) == "This workout can't be started.")
    }

    @Test func failureMessageMapsSessionErrorsAndFallsBackToGeneric() {
        #expect(SessionMessages.failureMessage(for: SessionError.alreadyActive) == SessionMessages.message(for: .alreadyActive))
        #expect(SessionMessages.failureMessage(for: SessionError.cannotStart) == SessionMessages.message(for: .cannotStart))
        #expect(SessionMessages.failureMessage(for: NSError(domain: "X", code: 1)) == ErrorMessages.generic)
        #expect(SessionMessages.failureMessage(for: NameError.empty) == ErrorMessages.generic)
    }

    // MARK: Screen labels

    @Test func screenLabelsReadAsTheSpecSays() {
        #expect(SessionMessages.elapsedTimeLabel == "Elapsed time")
        #expect(SessionMessages.pauseLabel == "Pause")
        #expect(SessionMessages.doneButton == "Done")
        #expect(SessionMessages.skipSetButton == "Skip Set")
        #expect(SessionMessages.restTitle == "Rest")
        #expect(SessionMessages.restRemainingLabel == "Rest remaining")
        #expect(SessionMessages.restRemainingCaption == "Remaining")
        #expect(SessionMessages.upNextTitle == "Up next")
        #expect(SessionMessages.skipRestButton == "Skip Rest")
        #expect(SessionMessages.undoButton == "Undo")
        #expect(SessionMessages.pausedTitle == "Paused")
        #expect(SessionMessages.resumeButton == "Resume")
    }
}
