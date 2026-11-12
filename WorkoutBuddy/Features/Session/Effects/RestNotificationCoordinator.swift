import Foundation

/// Makes the scheduled rest-end notification match the session state. It keeps only the latest desired
/// plan and applies it in one running task at a time: a state that arrives while a system call is in
/// flight is applied after it, and the states in between are skipped.
@MainActor
final class RestNotificationCoordinator {
    /// A cancel is skipped when it comes at or after the fire date, and at most this many seconds after it
    /// (see `apply`).
    static let cancelGuard: TimeInterval = 1

    /// A state's `lastActionAt` counts as the time of the user's action (and so as the decision time)
    /// only when it is at most this many seconds old when the state is reported. A report follows the
    /// save within milliseconds; an older stamp belongs to an earlier action (a launch or a came-back
    /// reconcile with no new action).
    static let actionReportWindow: TimeInterval = 1

    private let scheduler: any NotificationScheduling
    private let now: () -> Date
    private let log: (Error) -> Void

    /// The latest desired plan, with the time it was decided (when `reconcile` was called). The guard and
    /// the "covered" bookkeeping judge "before the fire date" by that time, not by when the plan is
    /// applied (a cancel is applied a fraction of a second after the user's tap).
    private var latest: (plan: RestNotificationPlan, removeDelivered: Bool, decidedAt: Date)?
    /// The `lastActionAt` of the previous reported state, to tell a new action from an old one.
    private var lastSeenActionAt: Date?
    private var task: Task<Void, Never>?
    /// The fire date of the notification this coordinator scheduled and hasn't cancelled, if any.
    private var scheduledFireDate: Date?
    /// The fire date of the last schedule that was added, kept until a cancel decided before that date, a
    /// failed schedule or a too-late one (for another fire date). Unlike `scheduledFireDate` it survives a cancel at or after the fire date (the
    /// reconcile when the user comes back), because the notification did alert for that rest.
    private var coveredFireDate: Date?

    /// `now` and `log` are injectable for tests. Failures are logged with the "session" category.
    init(
        scheduler: any NotificationScheduling,
        now: @escaping () -> Date = { Date.now },
        log: @escaping (Error) -> Void = { ErrorLogging.log($0, action: "Rest notification", category: "session") }
    ) {
        self.scheduler = scheduler
        self.now = now
        self.log = log
    }

    /// Reconciles the notification with `state`. `appBecameActive` marks the reconcile that runs when the
    /// app becomes active: only that one also removes delivered notifications, so a banner that just
    /// arrived isn't pulled away by an unrelated change. The mark isn't lost if a newer state replaces
    /// this one before it is applied.
    func reconcile(_ state: SessionEffectsState, settings: AppSettings.Values, appBecameActive: Bool = false) {
        let decidedAt = decisionTime(for: state)
        let plan = RestNotificationPlan.decide(state, settings: settings, now: decidedAt)
        uncoverIfDecidedBeforeFireDate(plan, decidedAt: decidedAt)
        // A newer state replaces the pending one, so it also brings its own decision time.
        latest = (plan, appBecameActive || (latest?.removeDelivered ?? false), decidedAt)
        guard task == nil else { return }
        task = Task { await run() }
    }

    /// When the change in `state` was decided. A user action stamps `lastActionAt` when it is made, but the
    /// report reaches `reconcile` a little later (a tap at 0.1 s before the fire date can be reported
    /// after it), so that stamp is the decision time. It counts only when it belongs to this state
    /// change: it is newer than the one the previous reported state carried (a came-back reconcile
    /// repeats the old stamp), not in the future, and at most `actionReportWindow` old (so the first
    /// report after a launch doesn't take an old action's time). Otherwise it is `now()`, which is also
    /// what `finishRest` gets: its stamp is the end time itself, at or after the fire date.
    private func decisionTime(for state: SessionEffectsState) -> Date {
        let current = now()
        guard case .active(_, let snapshot, _, _) = state, let action = snapshot.lastActionAt else { return current }
        let isNew = lastSeenActionAt.map { action > $0 } ?? true
        lastSeenActionAt = action
        guard isNew, action <= current, current.timeIntervalSince(action) <= Self.actionReportWindow else {
            return current
        }
        return action
    }

    /// A plan decided before the covered fire date that cancels the notification, or replaces it with one
    /// for another date, uncovers the rest right away, not when it is applied: until then the delegate
    /// could still play the alert for a rest the user has already skipped or paused.
    private func uncoverIfDecidedBeforeFireDate(_ plan: RestNotificationPlan, decidedAt: Date) {
        guard let covered = coveredFireDate, decidedAt < covered else { return }
        switch plan {
        case .cancel:
            coveredFireDate = nil
        case .schedule(let request) where request.fireDate != covered:
            coveredFireDate = nil
        case .schedule:
            break
        }
    }

    /// Whether the rest ending at `restEndsAt` is covered by a notification: a schedule for that date
    /// was added and no cancel was decided before it. A cancel decided at or after the date (even one past the 1 s guard)
    /// doesn't uncover it. Then the system decides who alerts at delivery, not the app.
    func isCovered(restEndsAt: Date) -> Bool {
        coveredFireDate == restEndsAt
    }

    /// Whether a rest-end notification is still expected to alert: some fire date is covered. The delegate
    /// asks it when iOS hands a notification over, so a rest skipped or paused just before the fire date
    /// (the cover is cleared at once, when the action is reported) plays no late alert.
    var isExpectingRestEnd: Bool {
        coveredFireDate != nil
    }

    /// Returns when everything reported so far has been applied. For tests.
    func waitUntilIdle() async {
        await task?.value
    }

    private func run() async {
        while let next = latest {
            latest = nil
            await apply(next.plan, removeDelivered: next.removeDelivered, decidedAt: next.decidedAt)
        }
        task = nil
    }

    /// The schedule or cancel goes first and `removeDelivered` after it: they are independent, and at a launch
    /// shortly before a rest ends every await counts (a schedule applied less than a second before the
    /// fire date comes too late).
    private func apply(_ plan: RestNotificationPlan, removeDelivered: Bool, decidedAt: Date) async {
        await applyPlan(plan, decidedAt: decidedAt)
        if removeDelivered { await scheduler.removeDelivered() }
    }

    private func applyPlan(_ plan: RestNotificationPlan, decidedAt: Date) async {
        switch plan {
        case .schedule(let request):
            do {
                switch try await scheduler.schedule(request) {
                case .added:
                    scheduledFireDate = request.fireDate
                    coveredFireDate = request.fireDate
                case .tooLate:
                    // Nothing was added. An earlier request for the same fire date may still be pending
                    // and then still covers it; otherwise this rest isn't covered.
                    if coveredFireDate != request.fireDate { coveredFireDate = nil }
                }
            } catch NotificationSchedulingError.notAllowed {
                scheduledFireDate = nil  // Expected while permission is denied; not logged.
                coveredFireDate = nil
            } catch {
                scheduledFireDate = nil
                coveredFireDate = nil
                log(error)
            }
        case .cancel:
            // A notification that has just fired is left alone (it's gone from the pending list by then,
            // and a cancel racing the fire date can't swallow the banner). A cancel decided before the
            // fire date always runs: it is a user action such as Pause or Skip Rest, and skipping it could
            // let a stale "Rest Over" fire. Judged by `decidedAt`, not by the time it is applied.
            let justFired = scheduledFireDate.map {
                let elapsed = decidedAt.timeIntervalSince($0)
                return elapsed >= 0 && elapsed <= Self.cancelGuard
            } ?? false
            if !justFired { await scheduler.cancel() }
            scheduledFireDate = nil
            // Only a cancel decided before the fire date uncovers the rest (Pause, Skip Rest, Undo...).
            if let covered = coveredFireDate, decidedAt < covered { coveredFireDate = nil }
        }
    }
}
