import Foundation

/// Display text for planned sets, built on `Formatters`. Every text has a visual form and a
/// spoken form for VoiceOver. Singular forms are handled here ("1 set", "1 rep").
nonisolated enum SetSummary {
    // MARK: One set

    /// "10 × 60 kg" or "10 × Bodyweight".
    static func line(_ values: SetValues, locale: Locale = .current) -> String {
        "\(values.reps) × \(Formatters.weight(values.kg, locale: locale))"
    }

    /// "10 reps at 60 kilograms" or "10 reps, bodyweight".
    static func spokenLine(_ values: SetValues, locale: Locale = .current) -> String {
        repsAndWeight(reps(values.reps), kg: values.kg, locale: locale)
    }

    // MARK: All sets of an exercise

    /// One line for list rows. Sets that match in reps and kg (rest isn't shown, so it isn't
    /// compared) read "3 × 10 × 60 kg" or "3 × 10 · Bodyweight". Otherwise it reads
    /// "3 sets · 8–12 reps · 60–80 kg", leaving out the range of a value that is the same in every set.
    static func summary(of sets: [SetValues], locale: Locale = .current) -> String {
        guard let first = sets.first else { return "No sets" }
        let weightText = Formatters.weight(first.kg, locale: locale)
        if sets.allSatisfy({ $0.reps == first.reps && $0.kg == first.kg }) {
            let separator = first.kg == 0 ? " · " : " × "
            return "\(sets.count) × \(first.reps)\(separator)\(weightText)"
        }

        let repValues = sets.map(\.reps)
        let kgValues = sets.map(\.kg)
        let minKg = kgValues.min() ?? 0
        let maxKg = kgValues.max() ?? 0
        let repsText = rangeText(repValues.min() ?? 0, repValues.max() ?? 0) { "\($0)" }
        let kgText = rangeText(minKg, maxKg) { Formatters.kg($0, locale: locale) }
        let weightPart = maxKg == 0 ? Formatters.weight(0, locale: locale) : kgText + "\u{00A0}kg"
        return [count(sets.count, "set"), "\(repsText) \(repValues.max() == 1 ? "rep" : "reps")", weightPart]
            .joined(separator: " · ")
    }

    /// "3 sets of 10 reps at 60 kilograms", "3 sets of 10 reps, bodyweight", or for sets that
    /// differ "3 sets, 8 to 12 reps, 60 to 80 kilograms".
    static func spokenSummary(of sets: [SetValues], locale: Locale = .current) -> String {
        guard let first = sets.first else { return "No sets" }
        if sets.allSatisfy({ $0.reps == first.reps && $0.kg == first.kg }) {
            return "\(count(sets.count, "set")) of \(repsAndWeight(reps(first.reps), kg: first.kg, locale: locale))"
        }

        let repValues = sets.map(\.reps)
        let kgValues = sets.map(\.kg)
        let minReps = repValues.min() ?? 0
        let maxReps = repValues.max() ?? 0
        let minKg = kgValues.min() ?? 0
        let maxKg = kgValues.max() ?? 0
        let repsText = minReps == maxReps
            ? reps(minReps)
            : "\(minReps) to \(reps(maxReps))"
        let weightText: String
        if maxKg == 0 {
            weightText = "bodyweight"
        } else if minKg == maxKg {
            weightText = Formatters.spokenWeight(minKg, locale: locale)
        } else {
            weightText = "\(Formatters.kg(minKg, locale: locale)) to \(Formatters.spokenWeight(maxKg, locale: locale))"
        }
        return [count(sets.count, "set"), repsText, weightText].joined(separator: ", ")
    }

    // MARK: Helpers

    /// "1 set", "3 sets". Regular nouns only.
    static func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(noun)\(number == 1 ? "" : "s")"
    }

    private static func reps(_ number: Int) -> String {
        count(number, "rep")
    }

    /// "10 reps at 60 kilograms" or "10 reps, bodyweight".
    private static func repsAndWeight(_ repsText: String, kg: Double, locale: Locale) -> String {
        kg == 0 ? "\(repsText), bodyweight" : "\(repsText) at \(Formatters.spokenWeight(kg, locale: locale))"
    }

    /// "10" when both ends are equal, otherwise "8–12".
    private static func rangeText<T: Equatable>(_ low: T, _ high: T, format: (T) -> String) -> String {
        low == high ? format(low) : "\(format(low))–\(format(high))"
    }
}
