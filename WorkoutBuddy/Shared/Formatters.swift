import Foundation

/// Locale-aware formatting of kg and rest values, and locale-independent parsing of typed kg text.
nonisolated enum Formatters {
    /// "22.5" in en_US, "22,5" in cs_CZ. No unit, at most one decimal.
    static func kg(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    }

    /// "22.5 kg" (with a non-breaking space, so "kg" never wraps alone), or "Bodyweight" for 0 kg. Use this wherever a weight is shown as text.
    static func weight(_ kg: Double, locale: Locale = .current) -> String {
        kg == 0 ? "Bodyweight" : "\(Formatters.kg(kg, locale: locale))\u{00A0}kg"
    }

    /// Spoken form for VoiceOver: "22.5 kilograms", "1 kilogram", or "bodyweight" for 0 kg.
    static func spokenWeight(_ kg: Double, locale: Locale = .current) -> String {
        if kg == 0 { return "bodyweight" }
        return "\(Formatters.kg(kg, locale: locale)) \(kg == 1 ? "kilogram" : "kilograms")"
    }

    /// "1:30" (minutes:seconds).
    static func rest(seconds: Int, locale: Locale = .current) -> String {
        Duration.seconds(max(seconds, 0)).formatted(.time(pattern: .minuteSecond).locale(locale))
    }

    /// Spoken form of `rest(seconds:)` for VoiceOver, e.g. "1 minute, 30 seconds". Whole workouts
    /// (hours, no seconds) use `spokenWorkoutDuration` instead.
    static func spokenDuration(seconds: Int, locale: Locale = .current) -> String {
        let total = max(seconds, 0)
        let units: Set<Duration.UnitsFormatStyle.Unit> = total < 60 ? [.seconds] : [.minutes, .seconds]
        return Duration.seconds(total).formatted(
            .units(allowed: units, width: .wide, zeroValueUnits: .hide).locale(locale)
        )
    }

    /// Length of a whole workout: "1 hr, 5 min", or "45 sec" under a minute. Uses the system's
    /// abbreviated units. Hours and minutes only: seconds are dropped from a minute on.
    /// The spoken form is `spokenWorkoutDuration`.
    static func duration(seconds: Int, locale: Locale = .current) -> String {
        formattedWorkoutDuration(seconds: seconds, width: .abbreviated, locale: locale)
    }

    /// Spoken form for VoiceOver: "1 hour, 5 minutes", "45 seconds".
    static func spokenWorkoutDuration(seconds: Int, locale: Locale = .current) -> String {
        formattedWorkoutDuration(seconds: seconds, width: .wide, locale: locale)
    }

    /// A total volume: "4,250 kg". Unlike `weight`, 0 stays "0 kg", because it's a total, not a set's weight.
    static func volume(_ kg: Double, locale: Locale = .current) -> String {
        "\(Formatters.kg(kg, locale: locale))\u{00A0}kg"
    }

    /// Spoken form for VoiceOver: "4,250 kilograms", "1 kilogram", "0 kilograms".
    static func spokenVolume(_ kg: Double, locale: Locale = .current) -> String {
        spokenKilograms(kg, locale: locale)
    }

    /// A kg amount read out, with no Bodyweight substitution (for editing controls and totals):
    /// "0 kilograms", "1 kilogram", "22.5 kilograms". Use `spokenWeight` for a set's weight.
    static func spokenKilograms(_ kg: Double, locale: Locale = .current) -> String {
        "\(Formatters.kg(kg, locale: locale)) \(kg == 1 ? "kilogram" : "kilograms")"
    }

    private static func formattedWorkoutDuration(
        seconds: Int, width: Duration.UnitsFormatStyle.UnitWidth, locale: Locale
    ) -> String {
        let total = max(seconds, 0)
        // Truncate to whole minutes ourselves so the style never rounds 59 min 40 s up to 1 hr.
        let shown = total < 60 ? total : total / 60 * 60
        let units: Set<Duration.UnitsFormatStyle.Unit> = total < 60 ? [.seconds] : [.hours, .minutes]
        return Duration.seconds(shown).formatted(
            .units(allowed: units, width: width, zeroValueUnits: .hide).locale(locale)
        )
    }

    /// Parses user-typed kg text. Both "." and "," are accepted as the decimal separator in every
    /// locale. Only ASCII digits plus at most one separator, with at most two fractional digits, are allowed (weights are at most 500, so there
    /// are no grouping separators). "22." and ".5" are accepted so a user mid-typing is understood.
    /// Everything else, including empty text, returns nil.
    static func parseKg(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        let digits = normalized.filter { $0 != "." }
        let parts = normalized.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        // At most two fractional digits: "1,000" is a grouped thousand, not a weight.
        guard !digits.isEmpty,
              normalized.count - digits.count <= 1,
              digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              parts.count < 2 || parts[1].count <= 2
        else { return nil }
        let parsed = Double(normalized.hasPrefix(".") ? "0" + normalized : normalized)
        guard let parsed, parsed.isFinite else { return nil }
        return parsed
    }

    /// Parses, snaps to the 0.5 grid and clamps. Nil when the text can't be parsed.
    static func snappedKg(from text: String) -> Double? {
        parseKg(text).map(AppSettings.snapKg)
    }

    /// The value a kg text field commits: the snapped parsed text, or `current` if it doesn't parse.
    static func committedKg(text: String, current: Double) -> Double {
        snappedKg(from: text) ?? current
    }

    /// Parses user-typed reps text: ASCII digits only, so no sign, separator or grouping. Surrounding
    /// whitespace is ignored. Nil for empty text, anything else, or a number too large for `Int`.
    static func parseReps(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(trimmed)
    }

    /// The value a reps text field commits: the parsed text clamped to `AppSettings.repsRange`, or
    /// `current` if it doesn't parse.
    static func committedReps(text: String, current: Int) -> Int {
        parseReps(text).map(AppSettings.clampReps) ?? current
    }
}
