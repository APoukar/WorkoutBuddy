import Foundation

/// Locale-aware formatting of kg and rest values, and locale-independent parsing of typed kg text.
nonisolated enum Formatters {
    /// "22.5" in en_US, "22,5" in cs_CZ. No unit, at most one decimal.
    static func kg(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    }

    /// "1:30" (minutes:seconds).
    static func rest(seconds: Int, locale: Locale = .current) -> String {
        Duration.seconds(max(seconds, 0)).formatted(.time(pattern: .minuteSecond).locale(locale))
    }

    /// Spoken form for VoiceOver, e.g. "1 minute, 30 seconds".
    static func spokenDuration(seconds: Int, locale: Locale = .current) -> String {
        let total = max(seconds, 0)
        let units: Set<Duration.UnitsFormatStyle.Unit> = total < 60 ? [.seconds] : [.minutes, .seconds]
        return Duration.seconds(total).formatted(
            .units(allowed: units, width: .wide, zeroValueUnits: .hide).locale(locale)
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

    /// Whether a kg text field's text must be rewritten after its value changed to `value`.
    /// Text that already stands for the value (using the `committedKg` rule, where empty or
    /// invalid text stands for `valueAtFocus`) is left alone so typing isn't disturbed.
    static func needsTextRewrite(text: String, value: Double, valueAtFocus: Double) -> Bool {
        committedKg(text: text, current: valueAtFocus) != value
    }
}
