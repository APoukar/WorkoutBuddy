import Foundation

/// When the rest-end alert (haptic and sound) should play. Pure, so it can be unit tested.
nonisolated enum RestAlertRules {
    /// How long after `restEndsAt` the app may notice the end and still count as "reached 0 while active".
    static let window: TimeInterval = 2

    /// The app's state when a rest ends, as the app sees it (the UIKit enum stays in the view).
    enum AppState: Equatable, Sendable {
        case active
        /// Still on screen, but not receiving events (Control Center or Notification Center is pulled down).
        case inactive
        case background
    }

    /// What to do when the rest end is noticed.
    enum RestEndAction: Equatable, Sendable {
        /// Leave the rest stored: the app is in the background, the notification fires, and the rest is
        /// cleared silently when the app becomes active.
        case leaveStored
        case clearSilently
        case clearAndPlayAlert
    }

    /// In the background the rest stays stored (clearing it would cancel the notification as it fires).
    /// Active or inactive: clear it. Who alerts is decided once, at delivery: when a notification covers
    /// this rest (`covered`), the system shows the banner or calls the delegate, which plays the in-app
    /// alert, so the app never plays one here. Only an uncovered rest gets the in-app alert, if the end
    /// was noticed on time.
    static func action(appState: AppState, restEndsAt: Date, noticedAt: Date, covered: Bool) -> RestEndAction {
        guard appState != .background else { return .leaveStored }
        guard !covered else { return .clearSilently }
        return shouldPlayAlert(restEndsAt: restEndsAt, noticedAt: noticedAt) ? .clearAndPlayAlert : .clearSilently
    }

    /// Play only when the app noticed the end within `window` seconds after it. A later notice means the
    /// app was suspended in the background when the rest ended: the next set simply shows, silently.
    static func shouldPlayAlert(restEndsAt: Date, noticedAt: Date) -> Bool {
        let late = noticedAt.timeIntervalSince(restEndsAt)
        return late >= 0 && late <= window
    }
}
