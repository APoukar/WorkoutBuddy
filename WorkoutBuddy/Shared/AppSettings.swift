import Foundation

/// Step used by the +/- buttons of the weight control. Every option keeps weights on the 0.5 kg grid.
nonisolated enum WeightStep: String, CaseIterable, Codable, Sendable, Identifiable {
    case half
    case one
    case twoAndHalf

    static let `default`: WeightStep = .twoAndHalf

    var id: String { rawValue }

    var kg: Double {
        switch self {
        case .half: 0.5
        case .one: 1
        case .twoAndHalf: 2.5
        }
    }

    var displayName: String {
        switch self {
        case .half: "0.5 kg"
        case .one: "1 kg"
        case .twoAndHalf: "2.5 kg"
        }
    }
}

/// Keys, defaults and valid ranges for the user settings (F9).
nonisolated enum AppSettings {
    enum Key {
        static let defaultReps = "settings.defaultReps"
        static let defaultKg = "settings.defaultKg"
        static let defaultRestSeconds = "settings.defaultRestSeconds"
        static let weightStep = "settings.weightStep"
        static let soundEnabled = "settings.soundEnabled"
        static let hapticsEnabled = "settings.hapticsEnabled"
    }

    enum Default {
        static let reps = 10
        static let kg = 20.0
        static let restSeconds = 90
        static let weightStep = WeightStep.default
        static let soundEnabled = true
        static let hapticsEnabled = true
    }

    static let repsRange = 1...100
    static let kgRange = 0.0...500.0
    static let restRange = 0...600
    /// All kg values lie on this grid.
    static let kgGrid = 0.5
    static let restStep = 15

    struct Values: Equatable, Sendable {
        var reps: Int
        var kg: Double
        var restSeconds: Int
        var weightStep: WeightStep
        var soundEnabled: Bool
        var hapticsEnabled: Bool
    }

    static func clampReps(_ value: Int) -> Int {
        min(max(value, repsRange.lowerBound), repsRange.upperBound)
    }

    static func clampRest(_ value: Int) -> Int {
        min(max(value, restRange.lowerBound), restRange.upperBound)
    }

    /// Snaps to the 0.5 kg grid and clamps to the valid range. Non-finite input becomes 0.
    static func snapKg(_ value: Double) -> Double {
        guard value.isFinite else { return kgRange.lowerBound }
        let snapped = (value / kgGrid).rounded() * kgGrid
        return min(max(snapped, kgRange.lowerBound), kgRange.upperBound)
    }

    /// Current settings with missing values defaulted and out-of-range values clamped.
    static func current(in defaults: UserDefaults = .standard) -> Values {
        let reps = defaults.object(forKey: Key.defaultReps) as? Int ?? Default.reps
        let kg = defaults.object(forKey: Key.defaultKg) as? Double ?? Default.kg
        let rest = defaults.object(forKey: Key.defaultRestSeconds) as? Int ?? Default.restSeconds
        let step = (defaults.string(forKey: Key.weightStep)).flatMap(WeightStep.init(rawValue:)) ?? Default.weightStep
        return Values(
            reps: clampReps(reps),
            kg: snapKg(kg),
            restSeconds: clampRest(rest),
            weightStep: step,
            soundEnabled: defaults.object(forKey: Key.soundEnabled) as? Bool ?? Default.soundEnabled,
            hapticsEnabled: defaults.object(forKey: Key.hapticsEnabled) as? Bool ?? Default.hapticsEnabled
        )
    }
}
