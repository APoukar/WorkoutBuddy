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
    /// Asks for notification permission if it hasn't been asked yet. Called after a successful Start.
    func requestNotificationPermissionIfNeeded()
    func notificationAuthorization() async -> NotificationAuthorization
}

/// Does nothing. Used by unit tests, UI-testing mode and previews, so they never schedule notifications,
/// show Live Activities or raise the permission prompt. It reports `.allowed`, so nothing permission-related shows.
struct NoSessionEffects: SessionEffects {
    func sessionChanged(_ state: SessionEffectsState) {}
    func requestNotificationPermissionIfNeeded() {}
    func notificationAuthorization() async -> NotificationAuthorization { .allowed }
}

/// Where the default `SessionEffects` comes from. The test / UI-testing / preview gate lives here, in one place.
enum SessionEffectsProvider {
    static let current: any SessionEffects = {
        if isInert(environment: ProcessInfo.processInfo.environment, uiTesting: UITestingLaunch.current) {
            return NoSessionEffects()
        }
        // Step 2b returns `LiveSessionEffects.shared` here.
        return NoSessionEffects()
    }()

    /// Whether the process must not reach the system: it hosts unit tests, runs in UI-testing mode, or
    /// renders Xcode previews.
    nonisolated static func isInert(environment: [String: String], uiTesting: UITestingLaunch?) -> Bool {
        ModelContainerFactory.isRunningTests(environment: environment)
            || uiTesting != nil
            || environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}
