import Foundation

/// The texts of the workout summary, built from the stats. Pure, so it can be unit tested.
/// The summary view gets only this value, never a model.
nonisolated struct SessionSummaryContent: Equatable, Sendable {
    var title: String
    var durationText: String
    var spokenDurationText: String
    var counts: [SessionMessages.CountLine]
    var volumeText: String
    var spokenVolumeText: String
    /// Whether Save is offered. Without a done set the summary offers Discard instead.
    var canSave: Bool

    init(_ stats: SessionStats, locale: Locale = .current) {
        // A workout that can't be saved (no done set) wasn't completed either.
        title = SessionMessages.summaryTitle(endedEarly: stats.endedEarly || !stats.canSave)
        durationText = SessionMessages.durationText(stats, locale: locale)
        spokenDurationText = SessionMessages.spokenDurationText(stats, locale: locale)
        counts = SessionMessages.countLines(for: stats)
        volumeText = SessionMessages.volumeText(stats, locale: locale)
        spokenVolumeText = SessionMessages.spokenVolumeText(stats, locale: locale)
        canSave = stats.canSave
    }
}
