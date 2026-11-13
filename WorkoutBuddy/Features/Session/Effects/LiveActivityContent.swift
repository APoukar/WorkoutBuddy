import Foundation

/// What the Live Activity shows for a session state: the content state and the stale date. Pure, so it
/// can be unit tested. Built with the same texts as the session screens.
nonisolated enum LiveActivityContent {
    typealias ContentState = WorkoutActivityAttributes.ContentState

    /// `nil` when there's no session (the activity must end). A rest that has run out but isn't cleared
    /// yet gives the set phase, like `SessionSnapshot.screen(now:)`. The stale date is the rest's end while
    /// a rest is running and not paused, otherwise `nil` (an update with `nil` makes a stale activity active).
    static func make(
        from state: SessionEffectsState, now: Date, locale: Locale = .current
    ) -> (state: ContentState, staleDate: Date?)? {
        guard case .active(_, let snapshot, let workoutName, let exerciseNames) = state else { return nil }

        let timer = ElapsedTimerInfo(
            startedAt: snapshot.startedAt, pausedDuration: snapshot.pausedDuration,
            pausedAt: snapshot.isPaused ? snapshot.pausedAt : nil)
        var content = ContentState(
            phase: .set,
            workoutName: workoutName ?? SessionMessages.fallbackWorkoutName,
            elapsedStart: timer.interval.lowerBound,
            pausedAt: timer.pausedAt)

        switch snapshot.screen(now: now) {
        case .set(let current):
            return setOrRest(
                content, at: current, rest: nil, snapshot: snapshot, exerciseNames: exerciseNames, now: now,
                locale: locale)
        case .rest(let next, let remaining):
            return setOrRest(
                content, at: next, rest: remaining, snapshot: snapshot, exerciseNames: exerciseNames, now: now,
                locale: locale)
        case .summary:
            let stats = SessionStats(snapshot, now: now)
            content.phase = .finished
            content.summaryTitle = SessionMessages.summaryTitle(endedEarly: stats.endedEarly || !stats.canSave)
            content.durationText = SessionMessages.durationText(stats, locale: locale)
            content.spokenDurationText = SessionMessages.spokenDurationText(stats, locale: locale)
            return (content, nil)
        }
    }

    /// The set and rest phases: `index` is the current set, or during a rest the next one, and `rest` is the
    /// seconds left of a running rest.
    private static func setOrRest(
        _ base: ContentState, at index: Int, rest: Int?, snapshot: SessionSnapshot,
        exerciseNames: [UUID: String], now: Date, locale: Locale
    ) -> (state: ContentState, staleDate: Date?) {
        var content = base
        let entry = snapshot.entries[index]
        let prefill = snapshot.prefill(forSetAt: index)
        let values = SetValues(reps: prefill.reps, kg: prefill.kg, restSeconds: entry.planned.restSeconds)
        let exerciseName = entry.exerciseID.flatMap { exerciseNames[$0] }
        content.exerciseName = exerciseName ?? SessionMessages.fallbackExerciseName
        content.position = SessionMessages.position(of: index, in: snapshot)
        content.spokenPosition = SessionMessages.spokenPosition(of: index, in: snapshot)
        content.setLine = SetSummary.line(values, locale: locale)
        content.spokenSetLine = SetSummary.spokenLine(values, locale: locale)

        guard let rest, let restEndsAt = snapshot.restEndsAt else {
            content.phase = snapshot.isPaused ? .paused : .set
            return (content, nil)
        }
        // The rest being counted is the planned rest of the set just done (the Undo target).
        let total = snapshot.undoTargetIndex(now: now).map { snapshot.entries[$0].planned.restSeconds } ?? rest
        let restInfo = RestTimerInfo(
            endsAt: restEndsAt, totalSeconds: total, pausedAt: snapshot.isPaused ? snapshot.pausedAt : nil)
        if snapshot.isPaused {
            content.phase = .paused
            content.frozenRestText = Formatters.rest(seconds: restInfo.frozenRemainingSeconds, locale: locale)
            return (content, nil)
        }
        content.phase = .rest
        content.upNext = SessionMessages.upNext(at: index, in: snapshot, exerciseName: exerciseName, locale: locale)
        content.spokenUpNext = SessionMessages.spokenUpNext(
            at: index, in: snapshot, exerciseName: exerciseName, locale: locale)
        content.restStart = restInfo.interval.lowerBound
        content.restEnd = restInfo.interval.upperBound
        return (content, restEndsAt)
    }
}
