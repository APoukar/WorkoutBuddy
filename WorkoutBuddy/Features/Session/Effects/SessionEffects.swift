import Foundation

/// What `SessionEffects` gets told after every saved session change: no session in progress, or the
/// session the active cover shows, as plain values. Names are looked up through the references at the
/// moment the state is built (names are never copied into the session), so a rename shows up in the next
/// state. `nil` / missing names mean the reference is gone; the consumers apply the fallbacks.
nonisolated enum SessionEffectsState: Equatable, Sendable {
    case none
    case active(sessionID: UUID, snapshot: SessionSnapshot, workoutName: String?, exerciseNames: [UUID: String])
}

/// The notification permission as the app sees it (the system enum stays in the live adapter).
nonisolated enum NotificationAuthorization: Equatable, Sendable {
    case notDetermined
    case allowed
    case denied
}

/// The side effects of a session that live outside the store: the rest-end notification and the Live
/// Activity. `SessionLibrary` reports the state after every successful save; the implementations make the
/// system match it (reconcile, not event tracking).
@MainActor
protocol SessionEffects {
    func sessionChanged(_ state: SessionEffectsState)
    /// The "came back to the app" reconcile: the same as `sessionChanged`, and it also removes rest-end
    /// notifications already delivered. Called at launch and when the app becomes active.
    func appBecameActive(_ state: SessionEffectsState)
    /// Asks for notification permission if it hasn't been asked yet. Called after a successful Start.
    func requestNotificationPermissionIfNeeded()
    func notificationAuthorization() async -> NotificationAuthorization
    /// Whether a rest-end notification will alert for the rest ending at `restEndsAt` (a schedule for that
    /// date succeeded and wasn't cancelled before it). When it does, the system decides who alerts at
    /// delivery, so the app doesn't play its own alert when it notices the end. Asked before the rest is
    /// cleared, because clearing it reconciles and may change the answer.
    func restEndAlertIsCovered(restEndsAt: Date) -> Bool
}

/// Does nothing. Used by unit tests, UI-testing mode and previews, so they never schedule notifications,
/// show Live Activities or raise the permission prompt. It reports `.allowed`, so nothing permission-related shows.
struct NoSessionEffects: SessionEffects {
    func sessionChanged(_ state: SessionEffectsState) {}
    func appBecameActive(_ state: SessionEffectsState) {}
    func requestNotificationPermissionIfNeeded() {}
    func notificationAuthorization() async -> NotificationAuthorization { .allowed }
    /// Nothing is ever scheduled, so the app plays the alert itself (phase 3 behaviour).
    func restEndAlertIsCovered(restEndsAt: Date) -> Bool { false }
}

/// Where the default `SessionEffects` comes from. The test / UI-testing / preview gate lives here, in one place.
enum SessionEffectsProvider {
    static let current: any SessionEffects = {
        if isInert(environment: ProcessInfo.processInfo.environment, uiTesting: UITestingLaunch.current) {
            return NoSessionEffects()
        }
        return LiveSessionEffects.shared
    }()

    /// Installs the notification delegate when the effects are live (never in tests, UI-testing mode or
    /// previews). Called from `WorkoutBuddyApp.init`, so the delegate is set before any notification arrives.
    static func install() {
        (current as? LiveSessionEffects)?.installDelegate()
    }

    /// Whether the process must not reach the system: it hosts unit tests, runs in UI-testing mode, or
    /// renders Xcode previews.
    nonisolated static func isInert(environment: [String: String], uiTesting: UITestingLaunch?) -> Bool {
        ModelContainerFactory.isRunningTests(environment: environment)
            || uiTesting != nil
            || environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}
