import Foundation
import OSLog
import SwiftData

/// Workout session operations. Every action is saved immediately (so a killed app can resume) and a
/// failed save is rolled back and rethrown. The decisions come from `SessionSnapshot`; this type
/// builds a snapshot from the models, decides, and writes back.
///
/// Every action first clears an expired rest, and does nothing (without throwing) when it doesn't apply
/// in the current state. Nothing applies to a finished session. The set actions (Done, Skip Set, Skip Rest,
/// Undo) also do nothing while paused, while a rest is running (Done, Skip Set), or when the set ID they were
/// given isn't the set they act on right now (a stale screen or a double tap). `finishRest` is not blocked
/// by a pause: it still clears a rest that expired before the pause.
@MainActor
struct SessionLibrary {
    let context: ModelContext

    // MARK: Queries

    /// The session with status `inProgress` (running, or finished and waiting for Save).
    /// If there are several (only possible through a bug), the newest `startedAt` wins and it's logged.
    func activeSession() throws -> WorkoutSession? {
        let inProgress = SessionStatus.inProgress.rawValue
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.statusRaw == inProgress },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        let sessions = try context.fetch(descriptor)
        if sessions.count > 1 {
            Logger(subsystem: ErrorLogging.subsystem, category: "session")
                .error("More than one session in progress: \(sessions.count, privacy: .public)")
        }
        return sessions.first
    }

    /// A value copy of the session, sets in session order (exercise by exercise, set by set).
    func snapshot(of session: WorkoutSession) -> SessionSnapshot {
        let exercises = session.orderedExercises
        var entries: [SessionSnapshot.Entry] = []
        for (exerciseIndex, exercise) in exercises.enumerated() {
            for (setIndex, set) in exercise.orderedSets.enumerated() {
                entries.append(
                    SessionSnapshot.Entry(
                        id: set.id,
                        exerciseIndex: exerciseIndex,
                        setIndex: setIndex,
                        exerciseID: exercise.exercise?.id,
                        planned: SetValues(reps: set.plannedReps, kg: set.plannedKg, restSeconds: set.plannedRestSeconds),
                        actualReps: set.actualReps,
                        actualKg: set.actualKg,
                        status: set.status,
                        completedAt: set.completedAt))
            }
        }
        return SessionSnapshot(
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            pausedDuration: session.pausedDuration,
            pausedAt: session.pausedAt,
            restEndsAt: session.restEndsAt,
            status: session.status,
            exerciseCount: exercises.count,
            entries: entries)
    }

    // MARK: Start

    /// Starts a session of the template, copying its planned numbers (names are never copied).
    /// Refuses before changing anything when a session is already in progress, or the template is
    /// soft-deleted or can't start. Rows without an exercise are skipped; the rest is renumbered from 0.
    @discardableResult
    func start(_ workout: Workout, now: Date = .now) throws -> WorkoutSession {
        if try activeSession() != nil { throw SessionError.alreadyActive }
        guard !workout.isSoftDeleted, WorkoutLibrary(context: context).canStart(workout) else {
            throw SessionError.cannotStart
        }

        do {
            let session = WorkoutSession(workout: nil, startedAt: now)
            context.insert(session)
            session.workout = workout

            let rows = workout.orderedExercises.filter { $0.exercise != nil }
            for (index, row) in rows.enumerated() {
                let sessionExercise = SessionExercise(order: index, exercise: nil)
                context.insert(sessionExercise)
                sessionExercise.session = session
                sessionExercise.exercise = row.exercise

                for (setIndex, planned) in row.orderedSets.enumerated() {
                    let set = SessionSet(
                        order: setIndex, plannedReps: planned.reps, plannedKg: planned.kg,
                        plannedRestSeconds: planned.restSeconds)
                    context.insert(set)
                    set.sessionExercise = sessionExercise
                }
            }

            try context.save()
            return session
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: Set actions

    /// Done: saves the shown reps and kg (clamped and snapped) as the actual values. Then the workout
    /// finishes if no set is left, a rest starts if the set has one, else the next set opens right away.
    func completeSet(in session: WorkoutSession, setID: UUID, reps: Int, kg: Double, now: Date = .now) throws {
        try perform(session, now: now) { snapshot in
            guard let set = currentSet(of: session, setID: setID, in: snapshot, now: now) else { return }
            set.actualReps = AppSettings.clampReps(reps)
            set.actualKg = AppSettings.snapKg(kg)
            set.status = .done
            set.completedAt = now
            if self.snapshot(of: session).currentSetIndex == nil {
                finish(session, now: now)
            } else if set.plannedRestSeconds > 0 {
                session.restEndsAt = now.addingTimeInterval(TimeInterval(set.plannedRestSeconds))
            }
        }
    }

    /// Skip Set: marks the set skipped (clearing actual values an Undo may have left) and stamps
    /// `completedAt`. Never starts a rest. Finishes the workout if it was the last set.
    func skipSet(in session: WorkoutSession, setID: UUID, now: Date = .now) throws {
        try perform(session, now: now) { snapshot in
            guard let set = currentSet(of: session, setID: setID, in: snapshot, now: now) else { return }
            set.status = .skipped
            set.actualReps = nil
            set.actualKg = nil
            set.completedAt = now
            if self.snapshot(of: session).currentSetIndex == nil {
                finish(session, now: now)
            }
        }
    }

    /// Skip Rest: ends a running rest, so the next set opens.
    func skipRest(in session: WorkoutSession, now: Date = .now) throws {
        try perform(session, now: now) { snapshot in
            guard !snapshot.isPaused else { return }
            session.restEndsAt = nil
        }
    }

    /// Undo: turns the set whose rest is running back to pending, keeping its actual values
    /// (the set screen opens with them) and clearing `completedAt` and the rest.
    func undo(in session: WorkoutSession, setID: UUID, now: Date = .now) throws {
        try perform(session, now: now) { snapshot in
            guard !snapshot.isPaused, let index = snapshot.undoTargetIndex(now: now),
                snapshot.entries[index].id == setID, let set = modelSet(id: setID, in: session)
            else { return }
            set.status = .pending
            set.completedAt = nil
            session.restEndsAt = nil
        }
    }

    /// The foreground auto-advance when the rest countdown reaches 0: clears an expired rest.
    /// Does nothing while the rest is still running.
    func finishRest(in session: WorkoutSession, now: Date = .now) throws {
        try perform(session, now: now) { _ in }
    }

    // MARK: Helpers

    /// Runs one action: does nothing on a finished session; otherwise clears an expired rest, runs `body`
    /// with a snapshot taken after that, and saves once. A failed save is rolled back and rethrown.
    private func perform(_ session: WorkoutSession, now: Date, _ body: (SessionSnapshot) -> Void) throws {
        guard session.endedAt == nil else { return }
        let before = snapshot(of: session)
        if let restEndsAt = before.restEndsAt, restEndsAt <= before.effectiveTime(now: now) {
            session.restEndsAt = nil
        }
        body(snapshot(of: session))
        do { try context.save() } catch { context.rollback(); throw error }
    }

    /// The model of the current (first pending) set, if the set actions apply right now and `setID` is
    /// that set: not paused and no rest running.
    private func currentSet(of session: WorkoutSession, setID: UUID, in snapshot: SessionSnapshot, now: Date)
        -> SessionSet?
    {
        guard !snapshot.isPaused, snapshot.restRemaining(now: now) == nil,
            let index = snapshot.currentSetIndex, snapshot.entries[index].id == setID
        else { return nil }
        return modelSet(id: setID, in: session)
    }

    private func modelSet(id: UUID, in session: WorkoutSession) -> SessionSet? {
        session.orderedExercises.flatMap(\.orderedSets).first { $0.id == id }
    }

    /// Ends the workout at `now`. Always clears the transient state, after folding a running pause
    /// into `pausedDuration`.
    private func finish(_ session: WorkoutSession, now: Date) {
        if let pausedAt = session.pausedAt {
            session.pausedDuration += max(0, now.timeIntervalSince(pausedAt))
        }
        session.endedAt = now
        session.pausedAt = nil
        session.restEndsAt = nil
    }
}
