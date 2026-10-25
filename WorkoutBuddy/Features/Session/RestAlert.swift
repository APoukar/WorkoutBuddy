import AudioToolbox
import OSLog
import UIKit

/// The rest-end alert, played while the app is in the foreground: a success haptic and the bundled
/// `RestEnd.caf` chime, each only if its Settings toggle is on. The sound follows the ring/silent
/// switch and mixes with music. Phase 4 reuses the same file for the notification sound.
@MainActor
enum RestAlert {
    /// Created once and reused. `nil` if the file is missing or can't be registered (logged, not fatal).
    private static let soundID: SystemSoundID? = {
        let log = Logger(subsystem: ErrorLogging.subsystem, category: "session")
        guard let url = Bundle.main.url(forResource: "RestEnd", withExtension: "caf") else {
            log.error("Rest-end sound RestEnd.caf is missing from the app bundle")
            return nil
        }
        var id: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &id)
        guard status == kAudioServicesNoError else {
            log.error("Rest-end sound could not be registered (OSStatus \(status, privacy: .public))")
            return nil
        }
        return id
    }()

    static func play(settings: AppSettings.Values = AppSettings.current()) {
        if settings.hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        if settings.soundEnabled, let soundID {
            AudioServicesPlaySystemSound(soundID)
        }
    }
}
