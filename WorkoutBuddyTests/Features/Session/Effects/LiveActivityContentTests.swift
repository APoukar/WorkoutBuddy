import Foundation
import Testing
@testable import WorkoutBuddy

struct LiveActivityContentTests {
    private let us = Locale(identifier: "en_US")
    private let enCZ = Locale(identifier: "en_CZ")
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let benchID = UUID()
    private let squatID = UUID()

    /// Bench Press: set 1 (10 x 60, done, rest 90), set 2 (8 x 62.5, pending). Back Squat: set 1 (5 x 0, pending).
    private func state(
        restEndsAt: Date? = nil, pausedAt: Date? = nil, endedAt: Date? = nil, pausedDuration: TimeInterval = 0,
        firstStatus: SetStatus = .done, secondStatus: SetStatus = .pending, squatStatus: SetStatus = .pending, squatKg: Double = 0,
        workoutName: String? = "Push Day", benchName: String? = "Bench Press"
    ) -> SessionEffectsState {
        func entry(_ exercise: Int, _ set: Int, _ id: UUID, _ values: SetValues, _ status: SetStatus) -> SessionSnapshot.Entry {
            .init(
                id: UUID(), exerciseIndex: exercise, setIndex: set, exerciseID: id, planned: values,
                actualReps: nil, actualKg: nil, status: status, completedAt: nil)
        }
        let snapshot = SessionSnapshot(
            startedAt: t0, endedAt: endedAt, pausedDuration: pausedDuration, pausedAt: pausedAt,
            restEndsAt: restEndsAt, exerciseCount: 2,
            entries: [
                entry(0, 0, benchID, SetValues(reps: 10, kg: 60, restSeconds: 90), firstStatus),
                entry(0, 1, benchID, SetValues(reps: 8, kg: 62.5, restSeconds: 90), secondStatus),
                entry(1, 0, squatID, SetValues(reps: 5, kg: squatKg, restSeconds: 120), squatStatus),
            ])
        var names = [squatID: "Back Squat"]
        names[benchID] = benchName
        return .active(sessionID: UUID(), snapshot: snapshot, workoutName: workoutName, exerciseNames: names)
    }

    private func make(_ state: SessionEffectsState, now: Date? = nil, locale: Locale? = nil)
        -> (state: WorkoutActivityAttributes.ContentState, staleDate: Date?) {
        LiveActivityContent.make(from: state, now: now ?? t0 + 10, locale: locale ?? us)!
    }

    // MARK: Phases

    @Test func noSessionGivesNothing() {
        #expect(LiveActivityContent.make(from: .none, now: t0) == nil)
    }

    @Test func setPhase() {
        let result = make(state())
        let content = result.state
        #expect(content.phase == .set)
        #expect(content.workoutName == "Push Day")
        #expect(content.exerciseName == "Bench Press")
        #expect(content.position == "Exercise 1 of 2 · Set 2 of 2")
        #expect(content.spokenPosition == "Exercise 1 of 2, set 2 of 2")
        #expect(content.setLine == "8 × 62.5\u{00A0}kg")
        #expect(content.spokenSetLine == "8 reps at 62.5 kilograms")
        #expect(content.elapsedStart == t0)
        #expect(content.pausedAt == nil)
        #expect(content.upNext == nil)
        #expect(content.restStart == nil && content.restEnd == nil)
        #expect(content.frozenRestText == nil)
        #expect(content.summaryTitle == nil && content.durationText == nil)
        #expect(result.staleDate == nil)
    }

    @Test func elapsedStartSkipsPausedTime() {
        #expect(make(state(pausedDuration: 30)).state.elapsedStart == t0 + 30)
    }

    @Test func restPhase() {
        let result = make(state(restEndsAt: t0 + 100))
        let content = result.state
        #expect(content.phase == .rest)
        #expect(content.exerciseName == "Bench Press")
        #expect(content.position == "Exercise 1 of 2 · Set 2 of 2")
        #expect(content.setLine == "8 × 62.5\u{00A0}kg")
        #expect(content.upNext == "Bench Press · Set 2 · 8 × 62.5\u{00A0}kg")
        #expect(content.spokenUpNext == "Bench Press, set 2, 8 reps at 62.5 kilograms")
        // The rest is the planned rest of the set just done: 90 s, ending at t0 + 100.
        #expect(content.restStart == t0 + 10)
        #expect(content.restEnd == t0 + 100)
        #expect(content.frozenRestText == nil)
        #expect(result.staleDate == t0 + 100)
    }

    @Test func expiredRestNotClearedGivesTheSetPhaseWithNoStaleDate() {
        let result = make(state(restEndsAt: t0 + 5), now: t0 + 20)
        #expect(result.state.phase == .set)
        #expect(result.state.upNext == nil)
        #expect(result.state.restEnd == nil)
        #expect(result.staleDate == nil)
    }

    @Test func pausedDuringASet() {
        let result = make(state(pausedAt: t0 + 8))
        #expect(result.state.phase == .paused)
        #expect(result.state.pausedAt == t0 + 8)
        #expect(result.state.frozenRestText == nil)
        #expect(result.state.restEnd == nil)
        #expect(result.state.setLine == "8 × 62.5\u{00A0}kg")
        #expect(result.staleDate == nil)
    }

    @Test func pausedDuringARest() {
        let result = make(state(restEndsAt: t0 + 100, pausedAt: t0 + 40), now: t0 + 500)
        let content = result.state
        #expect(content.phase == .paused)
        #expect(content.pausedAt == t0 + 40)
        // 60 s were left when it was paused.
        #expect(content.frozenRestText == "1:00")
        #expect(content.restStart == nil && content.restEnd == nil)
        #expect(content.upNext == nil)
        #expect(result.staleDate == nil)
    }

    @Test func finishedComplete() {
        let result = make(state(endedAt: t0 + 3_900, secondStatus: .done, squatStatus: .done), now: t0 + 9_000)
        let content = result.state
        #expect(content.phase == .finished)
        #expect(content.summaryTitle == "Workout Complete")
        #expect(content.durationText == "1 hr, 5 min")
        #expect(content.spokenDurationText == "1 hour, 5 minutes")
        #expect(content.exerciseName == nil && content.position == nil && content.setLine == nil)
        #expect(content.pausedAt == nil)
        #expect(result.staleDate == nil)
    }

    @Test func finishedEnded() {
        let result = make(state(pausedAt: t0 + 500, endedAt: t0 + 600))
        #expect(result.state.phase == .finished)
        #expect(result.state.summaryTitle == "Workout Ended")
        #expect(result.state.durationText == "10 min")
        #expect(result.state.pausedAt == nil)
    }

    @Test func finishedWithEverySetSkippedIsEnded() {
        let result = make(state(
            endedAt: t0 + 600, firstStatus: .skipped, secondStatus: .skipped, squatStatus: .skipped))
        #expect(result.state.phase == .finished)
        #expect(result.state.summaryTitle == "Workout Ended")
    }

    // MARK: Texts

    @Test func restAcrossExercisesDescribesTheNextExercisesSet() {
        // Bench set 2 is done, the rest leads into Back Squat set 1 (Bodyweight).
        let content = make(state(restEndsAt: t0 + 100, secondStatus: .done)).state
        #expect(content.phase == .rest)
        #expect(content.exerciseName == "Back Squat")
        #expect(content.position == "Exercise 2 of 2 · Set 1 of 1")
        #expect(content.setLine == "5 × Bodyweight")
        #expect(content.upNext == "Back Squat · Set 1 · 5 × Bodyweight")
    }

    @Test func bodyweightSet() {
        // Only the squat is left pending, with 0 kg.
        let content = make(state(secondStatus: .done, squatKg: 0)).state
        #expect(content.exerciseName == "Back Squat")
        #expect(content.setLine == "5 × Bodyweight")
        #expect(content.spokenSetLine == "5 reps, bodyweight")
        #expect(content.position == "Exercise 2 of 2 · Set 1 of 1")
    }

    @Test func missingNamesUseTheFallbacks() {
        let content = make(state(restEndsAt: t0 + 100, workoutName: nil, benchName: nil)).state
        #expect(content.workoutName == "Workout")
        #expect(content.exerciseName == "Exercise")
        #expect(content.upNext == "Exercise · Set 2 · 8 × 62.5\u{00A0}kg")
        #expect(content.spokenUpNext == "Exercise, set 2, 8 reps at 62.5 kilograms")
    }

    @Test func localeChangesTheDecimalSeparator() {
        #expect(make(state(), locale: us).state.setLine == "8 × 62.5\u{00A0}kg")
        #expect(make(state(), locale: enCZ).state.setLine == "8 × 62,5\u{00A0}kg")
        #expect(make(state(), locale: enCZ).state.spokenSetLine == "8 reps at 62,5 kilograms")
    }

    // MARK: Display phase

    @Test(arguments: [
        (WorkoutActivityAttributes.Phase.set, false, WorkoutActivityAttributes.DisplayPhase.set),
        (.set, true, .set),
        (.rest, false, .rest),
        (.rest, true, .restOver),
        (.paused, false, .paused),
        (.paused, true, .paused),
        (.finished, false, .finished),
        (.finished, true, .finished),
    ])
    func displayPhase(phase: WorkoutActivityAttributes.Phase, isStale: Bool, expected: WorkoutActivityAttributes.DisplayPhase) {
        var content = make(state()).state
        content.phase = phase
        #expect(content.displayPhase(isStale: isStale) == expected)
    }

    // MARK: Size

    @Test func encodedStateStaysUnder4KB() throws {
        let longName = String(repeating: "Incline Dumbbell Bench Press ", count: 4)
        let content = make(state(restEndsAt: t0 + 100, workoutName: longName, benchName: longName)).state
        let data = try JSONEncoder().encode(content)
        #expect(data.count < 4_096)
        #expect(try JSONDecoder().decode(WorkoutActivityAttributes.ContentState.self, from: data) == content)
    }
}
