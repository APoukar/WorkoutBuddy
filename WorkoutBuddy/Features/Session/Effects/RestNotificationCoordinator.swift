import Foundation

/// Makes the scheduled rest-end notification match the session state. It keeps only the latest desired
/// plan and applies it in one running task at a time: a state that arrives while a system call is in
/// flight is applied after it, and the states in between are skipped.
@MainActor
final class RestNotificationCoordinator {
    /// A cancel is skipped when it comes at or after the fire date, and at most this many seconds after it
    /// (see `apply`).
    static let cancelGuard: TimeInterval = 1

    private let scheduler: any NotificationScheduling
    private let now: () -> Date
    private let log: (Error) -> Void

    private var latest: (plan: RestNotificationPlan, removeDelivered: Bool)?
    private var task: Task<Void, Never>?
    /// The fire date of the notification this coordinator scheduled and hasn't cancelled, if any.
    private var scheduledFireDate: Date?

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
        let plan = RestNotificationPlan.decide(state, settings: settings, now: now())
        latest = (plan, appBecameActive || (latest?.removeDelivered ?? false))
        guard task == nil else { return }
        task = Task { await run() }
    }

    /// Returns when everything reported so far has been applied. For tests.
    func waitUntilIdle() async {
        await task?.value
    }

    private func run() async {
        while let next = latest {
            latest = nil
            await apply(next.plan, removeDelivered: next.removeDelivered)
        }
        task = nil
    }

    private func apply(_ plan: RestNotificationPlan, removeDelivered: Bool) async {
        if removeDelivered { await scheduler.removeDelivered() }
        switch plan {
        case .schedule(let request):
            do {
                try await scheduler.schedule(request)
                scheduledFireDate = request.fireDate
            } catch NotificationSchedulingError.notAllowed {
                scheduledFireDate = nil  // Expected while permission is denied; not logged.
            } catch {
                scheduledFireDate = nil
                log(error)
            }
        case .cancel:
            // A notification that has just fired is left alone (it's gone from the pending list by then,
            // and a cancel racing the fire date can't swallow the banner). A cancel before the fire date
            // always runs: it is a user action such as Pause or Skip Rest, and skipping it could let a
            // stale "Rest Over" fire.
            let justFired = scheduledFireDate.map {
                let elapsed = now().timeIntervalSince($0)
                return elapsed >= 0 && elapsed <= Self.cancelGuard
            } ?? false
            if !justFired { await scheduler.cancel() }
            scheduledFireDate = nil
        }
    }
}
