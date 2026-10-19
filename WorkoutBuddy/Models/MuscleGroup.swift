import Foundation

/// Muscle groups in the order the spec lists them. Used to group exercises.
nonisolated enum MuscleGroup: String, CaseIterable, Codable, Sendable {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case legs
    case glutes
    case core
    case fullBody

    var displayName: String {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .legs: "Legs"
        case .glutes: "Glutes"
        case .core: "Core"
        case .fullBody: "Full body"
        }
    }
}
