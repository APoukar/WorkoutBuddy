import Foundation

/// The numbers of one planned set: reps, weight and rest after the set. Templates use it now;
/// sessions copy it later, so a template can change without touching past sessions.
nonisolated struct SetValues: Equatable, Hashable, Sendable {
    var reps: Int
    var kg: Double
    var restSeconds: Int
}
