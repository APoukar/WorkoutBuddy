import Foundation

/// What the session UI should show right now.
nonisolated enum SessionScreen: Equatable, Sendable {
    /// The set screen for the entry at this index (into `SessionSnapshot.entries`).
    case set(Int)
    /// The rest screen: the index of the next set, and the whole seconds left.
    case rest(next: Int, remaining: Int)
    /// The workout is over and waiting for Save or Discard.
    case summary
}

/// A value copy of a workout session: its timing fields and every set in order. All decisions about
/// what is on screen, what Undo reverts and the stats are pure functions of a snapshot and a time,
/// so they can be unit tested without SwiftData. `SessionLibrary` builds one from the models.
nonisolated struct SessionSnapshot: Equatable, Sendable {
    /// One set of the session. Named `Entry`, not `Set`, so it doesn't shadow `Swift.Set`.
    struct Entry: Equatable, Sendable, Identifiable {
        var id: UUID
        /// Position of the set's exercise within the session.
        var exerciseIndex: Int
        /// Position of the set within its exercise.
        var setIndex: Int
        /// The exercise to look the name up from. `nil` only if the reference is gone.
        var exerciseID: UUID?
        var planned: SetValues
        var actualReps: Int?
        var actualKg: Double?
        var status: SetStatus
        /// When the set was resolved (done or skipped).
        var completedAt: Date?
    }

    var startedAt: Date
    var endedAt: Date?
    var pausedDuration: TimeInterval = 0
    var pausedAt: Date?
    var restEndsAt: Date?
    /// When the user last acted on the session (see `WorkoutSession.lastActionAt`).
    var lastActionAt: Date?
    var status: SessionStatus = .inProgress
    var exerciseCount: Int
    /// Every set, in session order (exercise by exercise, set by set).
    var entries: [Entry]

    // MARK: Structure

    func setCount(ofExercise exerciseIndex: Int) -> Int {
        entries.filter { $0.exerciseIndex == exerciseIndex }.count
    }

    // MARK: Time

    /// The moment all derived values are computed at. A finished session is frozen at `endedAt`,
    /// a paused one at `pausedAt`.
    func effectiveTime(now: Date) -> Date {
        endedAt ?? pausedAt ?? now
    }

    /// Time spent working out: excludes pauses. Never negative.
    func elapsed(now: Date) -> TimeInterval {
        max(0, effectiveTime(now: now).timeIntervalSince(startedAt) - pausedDuration)
    }

    /// Whole seconds left of the rest, rounded up so it reads 0:01 until it really ends.
    /// `nil` when there's no rest or it has expired.
    func restRemaining(now: Date) -> Int? {
        guard let restEndsAt else { return nil }
        let remaining = restEndsAt.timeIntervalSince(effectiveTime(now: now))
        guard remaining > 0 else { return nil }
        return Int(remaining.rounded(.up))
    }

    /// A rest that has run out but hasn't been cleared yet (the app was in the background, say).
    func hasExpiredRest(now: Date) -> Bool {
        guard !isFinished, let restEndsAt else { return false }
        return restEndsAt <= effectiveTime(now: now)
    }

    /// When the foreground auto-advance should clear the rest: `restEndsAt`, but never while paused or
    /// finished (a paused rest is frozen and a finished workout has no rest). `nil` when there's nothing to wait for.
    var autoAdvanceDeadline: Date? {
        guard !isPaused, !isFinished else { return nil }
        return restEndsAt
    }

    // MARK: State

    var isFinished: Bool { endedAt != nil }

    /// A finished session is never paused, even if `pausedAt` were left set.
    var isPaused: Bool { pausedAt != nil && endedAt == nil }

    var hasDoneSet: Bool { entries.contains { $0.status == .done } }

    /// The first pending set. Sets are always done in order.
    var currentSetIndex: Int? {
        entries.firstIndex { $0.status == .pending }
    }

    func screen(now: Date) -> SessionScreen {
        // Nothing left to do: the workout is over (or the data is empty).
        guard !isFinished, let current = currentSetIndex else { return .summary }
        if let remaining = restRemaining(now: now) {
            return .rest(next: current, remaining: remaining)
        }
        return .set(current)
    }

    /// The done set whose rest is running, i.e. the one right before the current set. `nil` unless resting.
    func undoTargetIndex(now: Date) -> Int? {
        guard !isFinished, restRemaining(now: now) != nil, let current = currentSetIndex else { return nil }
        let previous = current - 1
        guard entries.indices.contains(previous), entries[previous].status == .done else { return nil }
        return previous
    }

    /// The reps and kg to start the set screen with: the actual values if present (after an Undo), else the plan.
    func prefill(forSetAt index: Int) -> (reps: Int, kg: Double) {
        let entry = entries[index]
        return (entry.actualReps ?? entry.planned.reps, entry.actualKg ?? entry.planned.kg)
    }

    // MARK: Review

    /// The sets that can be looked at in review: done or skipped, in order. Not-performed and pending sets
    /// never are. While the workout runs only sets before the current one count (sets are done in order);
    /// once it's finished, all of them do.
    var reviewableIndices: [Int] {
        let limit = isFinished ? entries.count : (currentSetIndex ?? entries.count)
        return (0..<limit).filter { entries[$0].status == .done || entries[$0].status == .skipped }
    }

    /// The reviewable set with this ID, or `nil` when there's no such set or it can't be reviewed (any more).
    func reviewIndex(ofSetWithID id: UUID?) -> Int? {
        guard let id else { return nil }
        return reviewableIndices.first { entries[$0].id == id }
    }

    /// The next older reviewable set. `from == nil` means the current set or the summary, so this is the
    /// newest reviewable set. `nil` when there's none (or `from` is the oldest).
    func previousReviewIndex(from index: Int?) -> Int? {
        let indices = reviewableIndices
        guard let index else { return indices.last }
        return indices.last { $0 < index }
    }

    /// The next newer reviewable set. `nil` past the newest one (or from `nil`): back to the current set or the summary.
    func nextReviewIndex(from index: Int?) -> Int? {
        guard let index else { return nil }
        return reviewableIndices.first { $0 > index }
    }

    /// The last moment the user did something: `pausedAt` if paused, else the latest of the last action
    /// (Done, Skip, Skip Rest, Undo, Pause, Resume, ...), the resolution of a done or skipped set, and the
    /// start. Used to end an interrupted workout at a sensible time.
    var lastActivity: Date {
        if let pausedAt { return pausedAt }
        let resolved = entries
            .filter { $0.status == .done || $0.status == .skipped }
            .compactMap(\.completedAt)
        return (resolved + [lastActionAt, startedAt].compactMap { $0 }).max() ?? startedAt
    }
}
