import Foundation

/// A rest-end notification to schedule. Plain values only; the live adapter turns it into a
/// `UNNotificationRequest`.
nonisolated struct RestNotificationRequest: Equatable, Sendable {
    /// Which sound the notification plays. A notification without any sound doesn't vibrate either.
    enum Sound: Equatable, Sendable {
        /// The bundled chime (the iPhone also vibrates according to its own settings).
        case chime
        /// The bundled silent sound: the iPhone vibrates without a chime.
        case silent
        /// No sound at all: a silent banner.
        case none
    }

    /// When the rest ends.
    var fireDate: Date
    var title: String
    var body: String
    var sound: Sound
}

/// What the rest-end notification should be right now. Pure, so it can be unit tested.
nonisolated enum RestNotificationPlan: Equatable, Sendable {
    case schedule(RestNotificationRequest)
    case cancel

    /// Schedule while the session is resting and not paused (and not finished); cancel otherwise.
    /// The body is the rest screen's "Up next" line; names come from `state`, with the fallbacks applied.
    static func decide(
        _ state: SessionEffectsState, settings: AppSettings.Values, now: Date, locale: Locale = .current
    ) -> RestNotificationPlan {
        guard case .active(_, let snapshot, _, let exerciseNames) = state,
            !snapshot.isPaused, !snapshot.isFinished,
            case .rest(let next, _) = snapshot.screen(now: now),
            let fireDate = snapshot.restEndsAt
        else { return .cancel }

        let exerciseName = snapshot.entries[next].exerciseID.flatMap { exerciseNames[$0] }
        return .schedule(RestNotificationRequest(
            fireDate: fireDate,
            title: SessionMessages.restOverNotificationTitle,
            body: SessionMessages.upNext(at: next, in: snapshot, exerciseName: exerciseName, locale: locale),
            sound: sound(for: settings)))
    }

    /// Sound on: the chime. Sound off and Haptics on: the silent sound, so the phone still vibrates.
    /// Both off: no sound.
    static func sound(for settings: AppSettings.Values) -> RestNotificationRequest.Sound {
        if settings.soundEnabled { return .chime }
        return settings.hapticsEnabled ? .silent : .none
    }
}
