import Foundation
import Testing
@testable import WorkoutBuddy

struct RestNotificationPlanTests {
    private let us = Locale(identifier: "en_US")
    private let enCZ = Locale(identifier: "en_CZ")
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let benchID = UUID()
    private let squatID = UUID()

    private let soundOn = AppSettings.Values(
        reps: 10, kg: 20, restSeconds: 90, weightStep: .twoAndHalf, soundEnabled: true, hapticsEnabled: true)

    private func settings(sound: Bool, haptics: Bool) -> AppSettings.Values {
        var values = soundOn
        values.soundEnabled = sound
        values.hapticsEnabled = haptics
        return values
    }

    /// Bench Press: set 1 (10 x 60, done), set 2 (8 x 62.5, pending). Back Squat: set 1 (5 x 100, pending).
    private func state(
        restEndsAt: Date? = nil, pausedAt: Date? = nil, endedAt: Date? = nil,
        nextKg: Double = 62.5, benchName: String? = "Bench Press"
    ) -> SessionEffectsState {
        func entry(_ exercise: Int, _ set: Int, _ id: UUID, _ values: SetValues, _ status: SetStatus) -> SessionSnapshot.Entry {
            .init(
                id: UUID(), exerciseIndex: exercise, setIndex: set, exerciseID: id, planned: values,
                actualReps: nil, actualKg: nil, status: status, completedAt: nil)
        }
        let snapshot = SessionSnapshot(
            startedAt: t0, endedAt: endedAt, pausedAt: pausedAt, restEndsAt: restEndsAt, exerciseCount: 2,
            entries: [
                entry(0, 0, benchID, SetValues(reps: 10, kg: 60, restSeconds: 90), .done),
                entry(0, 1, benchID, SetValues(reps: 8, kg: nextKg, restSeconds: 90), .pending),
                entry(1, 0, squatID, SetValues(reps: 5, kg: 100, restSeconds: 120), .pending),
            ])
        var names = [squatID: "Back Squat"]
        names[benchID] = benchName
        return .active(sessionID: UUID(), snapshot: snapshot, workoutName: "Push Day", exerciseNames: names)
    }

    private func decide(
        _ state: SessionEffectsState, now: Date? = nil, settings: AppSettings.Values? = nil, locale: Locale? = nil
    ) -> RestNotificationPlan {
        RestNotificationPlan.decide(state, settings: settings ?? soundOn, now: now ?? t0 + 10, locale: locale ?? us)
    }

    // MARK: Decision

    @Test func restingSchedulesAtTheEndOfTheRest() {
        let plan = decide(state(restEndsAt: t0 + 100))
        #expect(plan == .schedule(RestNotificationRequest(
            fireDate: t0 + 100,
            title: "Rest Over",
            body: "Bench Press · Set 2 · 8 × 62.5\u{00A0}kg",
            sound: .chime)))
    }

    @Test func aRunningSetCancels() {
        #expect(decide(state()) == .cancel)
    }

    @Test func anExpiredRestCancels() {
        #expect(decide(state(restEndsAt: t0 + 100), now: t0 + 100) == .cancel)
        #expect(decide(state(restEndsAt: t0 + 100), now: t0 + 500) == .cancel)
        // One tick before the end it still schedules.
        #expect(decide(state(restEndsAt: t0 + 100), now: t0 + 99.5) != .cancel)
    }

    @Test func aPausedRestCancels() {
        #expect(decide(state(restEndsAt: t0 + 100, pausedAt: t0 + 20), now: t0 + 30) == .cancel)
    }

    @Test func aFinishedSessionCancelsEvenWithARestLeftOver() {
        #expect(decide(state(restEndsAt: t0 + 100, endedAt: t0 + 20), now: t0 + 30) == .cancel)
    }

    @Test func noSessionCancels() {
        #expect(decide(.none) == .cancel)
    }

    @Test func aResumedRestSchedulesAtTheShiftedEnd() {
        // Resume moves `restEndsAt` and clears `pausedAt`; the plan just follows the stored state.
        #expect(decide(state(restEndsAt: t0 + 120), now: t0 + 50) != .cancel)
        guard case .schedule(let request) = decide(state(restEndsAt: t0 + 120), now: t0 + 50) else {
            Issue.record("Expected a schedule")
            return
        }
        #expect(request.fireDate == t0 + 120)
    }

    // MARK: Sound

    @Test func soundForEachSettingsCombination() {
        #expect(RestNotificationPlan.sound(for: settings(sound: true, haptics: true)) == .chime)
        #expect(RestNotificationPlan.sound(for: settings(sound: true, haptics: false)) == .chime)
        #expect(RestNotificationPlan.sound(for: settings(sound: false, haptics: true)) == .silent)
        #expect(RestNotificationPlan.sound(for: settings(sound: false, haptics: false)) == RestNotificationRequest.Sound.none)
    }

    @Test func theRequestCarriesTheSound() {
        let resting = state(restEndsAt: t0 + 100)
        for (sound, haptics, expected) in [
            (true, true, RestNotificationRequest.Sound.chime), (false, true, .silent), (false, false, .none),
        ] {
            guard case .schedule(let request) = decide(resting, settings: settings(sound: sound, haptics: haptics)) else {
                Issue.record("Expected a schedule")
                return
            }
            #expect(request.sound == expected)
        }
    }

    // MARK: Body

    @Test func aBodyweightSetReadsBodyweight() {
        guard case .schedule(let request) = decide(state(restEndsAt: t0 + 100, nextKg: 0)) else {
            Issue.record("Expected a schedule")
            return
        }
        #expect(request.body == "Bench Press · Set 2 · 8 × Bodyweight")
    }

    @Test func aMissingExerciseNameUsesTheFallback() {
        guard case .schedule(let request) = decide(state(restEndsAt: t0 + 100, benchName: nil)) else {
            Issue.record("Expected a schedule")
            return
        }
        #expect(request.body == "Exercise · Set 2 · 8 × 62.5\u{00A0}kg")
    }

    @Test func numbersFollowTheLocale() {
        guard case .schedule(let request) = decide(state(restEndsAt: t0 + 100), locale: enCZ) else {
            Issue.record("Expected a schedule")
            return
        }
        #expect(request.body == "Bench Press · Set 2 · 8 × 62,5\u{00A0}kg")
    }

    @Test func theUpNextSetIsTheCurrentSetEvenInTheNextExercise() {
        // Bench set 2 done as well: the next set is Back Squat's.
        guard case .active(let id, var snapshot, let workoutName, let names) = state(restEndsAt: t0 + 100) else { return }
        snapshot.entries[1].status = .done
        let plan = decide(.active(sessionID: id, snapshot: snapshot, workoutName: workoutName, exerciseNames: names))
        guard case .schedule(let request) = plan else {
            Issue.record("Expected a schedule")
            return
        }
        #expect(request.body == "Back Squat · Set 1 · 5 × 100\u{00A0}kg")
    }
}
