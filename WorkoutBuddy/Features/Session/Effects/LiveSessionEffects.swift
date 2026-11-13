import Foundation
import UserNotifications

/// The real `SessionEffects`: fans the session state out to the coordinators and talks to the notification
/// center. Used outside unit tests, UI-testing mode and previews (see `SessionEffectsProvider`).
@MainActor
final class LiveSessionEffects: SessionEffects {
    static let shared = LiveSessionEffects()

    private let scheduler: any NotificationScheduling
    private let coordinator: RestNotificationCoordinator
    private let settings: () -> AppSettings.Values
    /// Held strongly: `UNUserNotificationCenter.delegate` is weak.
    private let delegate: RestNotificationDelegate
    private var delegateInstalled = false
    private let log: (Error) -> Void
    private var permissionTask: Task<Void, Never>?

    init(
        scheduler: any NotificationScheduling = UserNotificationScheduler(),
        settings: @escaping () -> AppSettings.Values = { AppSettings.current() },
        log: @escaping (Error) -> Void = {
            ErrorLogging.log($0, action: "Notification permission request", category: "session")
        }
    ) {
        self.log = log
        self.scheduler = scheduler
        let coordinator = RestNotificationCoordinator(scheduler: scheduler)
        self.coordinator = coordinator
        self.delegate = RestNotificationDelegate(restEndIsExpected: { coordinator.isExpectingRestEnd })
        self.settings = settings
    }

    /// Makes the delegate the notification center's delegate, once. Called at launch, so it's set before
    /// any notification arrives. Never called from `init`, so tests can create instances freely.
    func installDelegate() {
        guard !delegateInstalled else { return }
        delegateInstalled = true
        UNUserNotificationCenter.current().delegate = delegate
    }

    func sessionChanged(_ state: SessionEffectsState) {
        coordinator.reconcile(state, settings: settings())
    }

    func appBecameActive(_ state: SessionEffectsState) {
        coordinator.reconcile(state, settings: settings(), appBecameActive: true)
    }

    /// Returns when everything reported so far has been applied, and a permission request has finished.
    /// For tests.
    func waitUntilIdle() async {
        await coordinator.waitUntilIdle()
        await permissionTask?.value
    }

    /// Asks only while the status is `.notDetermined`; a failed request is logged, never thrown.
    func requestNotificationPermissionIfNeeded() {
        let scheduler = scheduler
        let log = log
        permissionTask = Task {
            guard await scheduler.authorization() == .notDetermined else { return }
            do {
                try await scheduler.requestAuthorization()
            } catch {
                log(error)
            }
        }
    }

    func notificationAuthorization() async -> NotificationAuthorization {
        await scheduler.authorization()
    }

    /// Whether a rest-end notification is still expected to alert (see `RestNotificationCoordinator`).
    var restEndIsExpected: Bool { coordinator.isExpectingRestEnd }

    func restEndAlertIsCovered(restEndsAt: Date) -> Bool {
        coordinator.isCovered(restEndsAt: restEndsAt)
    }
}
