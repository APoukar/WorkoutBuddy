import Foundation

/// When the rest-end alert (haptic and sound) should play. Pure, so it can be unit tested.
nonisolated enum RestAlertRules {
    /// How long after `restEndsAt` the app may notice the end and still count as "reached 0 while active".
    static let window: TimeInterval = 2

    /// Play only when the app noticed the end within `window` seconds after it. A later notice means the
    /// app was suspended in the background when the rest ended: the next set simply shows, silently.
    static func shouldPlayAlert(restEndsAt: Date, noticedAt: Date) -> Bool {
        let late = noticedAt.timeIntervalSince(restEndsAt)
        return late >= 0 && late <= window
    }
}
